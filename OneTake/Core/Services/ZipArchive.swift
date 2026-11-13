import Foundation
import Compression

/// Writes a standards-compliant, store-only ZIP without loading video files into memory.
/// ZIP64 is intentionally not implemented; a single archive and each entry must fit classic ZIP limits.
enum ZipArchive {
    struct Entry {
        let name: String
        let fileURL: URL
    }

    enum ArchiveError: LocalizedError {
        case tooLarge(String)
        case invalid(String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let name): "\(name) is too large to include in this ZIP archive."
            case .invalid(let reason): "This backup archive is invalid: \(reason)"
            case .unsupported(let reason): "This ZIP format is not supported: \(reason)"
            }
        }
    }

    private struct CentralEntry {
        let name: Data
        let checksum: UInt32
        let size: UInt32
        let offset: UInt32
    }

    static func write(_ entries: [Entry], to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scratch = url.deletingLastPathComponent().appendingPathComponent(".zip-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: scratch) }

        let output = try FileHandle(forWritingTo: createEmptyFile(at: scratch))
        defer { try? output.close() }
        var centralEntries: [CentralEntry] = []
        var offset: UInt64 = 0

        for entry in entries {
            let attrs = try manager.attributesOfItem(atPath: entry.fileURL.path)
            guard let fileSize = attrs[.size] as? NSNumber, fileSize.uint64Value <= UInt32.max,
                  offset <= UInt32.max else { throw ArchiveError.tooLarge(entry.name) }
            let size = UInt32(fileSize.uint64Value)
            let name = Data(entry.name.utf8)
            guard name.count <= UInt16.max else { throw ArchiveError.tooLarge(entry.name) }
            let checksum = try crc32(of: entry.fileURL)

            var header = Data()
            appendUInt32(0x04034b50, to: &header)
            appendUInt16(20, to: &header)
            appendUInt16(0x0800, to: &header) // UTF-8 file name
            appendUInt16(0, to: &header) // store, no compression
            appendUInt16(0, to: &header); appendUInt16(0, to: &header)
            appendUInt32(checksum, to: &header)
            appendUInt32(size, to: &header); appendUInt32(size, to: &header)
            appendUInt16(UInt16(name.count), to: &header); appendUInt16(0, to: &header)
            header.append(name)
            try output.write(contentsOf: header)
            offset += UInt64(header.count)
            try copy(entry.fileURL, to: output)
            centralEntries.append(CentralEntry(name: name, checksum: checksum, size: size, offset: UInt32(offset - UInt64(header.count))))
            offset += UInt64(size)
        }

        guard centralEntries.count <= Int(UInt16.max), offset <= UInt32.max else {
            throw ArchiveError.tooLarge(url.lastPathComponent)
        }
        let centralStart = UInt32(offset)
        for entry in centralEntries {
            var record = Data()
            appendUInt32(0x02014b50, to: &record)
            appendUInt16(20, to: &record); appendUInt16(20, to: &record)
            appendUInt16(0x0800, to: &record); appendUInt16(0, to: &record)
            appendUInt16(0, to: &record); appendUInt16(0, to: &record)
            appendUInt32(entry.checksum, to: &record)
            appendUInt32(entry.size, to: &record); appendUInt32(entry.size, to: &record)
            appendUInt16(UInt16(entry.name.count), to: &record)
            appendUInt16(0, to: &record); appendUInt16(0, to: &record)
            appendUInt16(0, to: &record); appendUInt16(0, to: &record)
            appendUInt32(0, to: &record); appendUInt32(entry.offset, to: &record)
            record.append(entry.name)
            try output.write(contentsOf: record)
            offset += UInt64(record.count)
        }
        let centralSize = UInt32(offset - UInt64(centralStart))
        var end = Data()
        appendUInt32(0x06054b50, to: &end)
        appendUInt16(0, to: &end); appendUInt16(0, to: &end)
        appendUInt16(UInt16(centralEntries.count), to: &end)
        appendUInt16(UInt16(centralEntries.count), to: &end)
        appendUInt32(centralSize, to: &end); appendUInt32(centralStart, to: &end)
        appendUInt16(0, to: &end)
        try output.write(contentsOf: end)
        try output.synchronize()
        try? manager.removeItem(at: url)
        try manager.moveItem(at: scratch, to: url)
    }

    static func write(_ entries: [(name: String, data: Data)], to url: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var fileEntries: [Entry] = []
        for (name, data) in entries {
            let fileURL = tempDir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
            try data.write(to: fileURL)
            fileEntries.append(Entry(name: name, fileURL: fileURL))
        }
        try write(fileEntries, to: url)
    }

    private struct CentralDirectoryEntry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let checksum: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    /// Extracts store (`method == 0`) and deflate (`method == 8`) ZIP archives (including streaming
    /// entries whose sizes live in the central directory). Paths are validated before writing so an
    /// imported archive cannot escape its staging directory.
    static func extract(
        from archiveURL: URL,
        to destination: URL,
        maxExtractedBytes: UInt64 = 8 * 1024 * 1024 * 1024,
        maxEntryCount: Int = 20_000
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: archiveURL)
        var succeeded = false
        defer {
            try? input.close()
            if !succeeded { try? manager.removeItem(at: destination) }
        }

        let archiveSize = UInt64((try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let entries = try readCentralDirectory(from: input, archiveSize: archiveSize, maxEntryCount: maxEntryCount)
        guard !entries.isEmpty else { throw ArchiveError.invalid("archive is empty") }

        var extractedBytes: UInt64 = 0
        var entryCount = 0
        let standardizedRoot = destination.standardizedFileURL.path + "/"

        for entry in entries {
            guard entry.flags & 0x0001 == 0 else {
                throw ArchiveError.unsupported("encrypted entries")
            }
            guard entry.method == 0 || entry.method == 8 else {
                throw ArchiveError.unsupported("compression method \(entry.method)")
            }
            if entry.method == 0 && entry.compressedSize != entry.uncompressedSize {
                throw ArchiveError.invalid("mismatched store entry sizes")
            }

            let components = entry.name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !entry.name.hasPrefix("/"), !entry.name.contains("\\"), !components.isEmpty,
                  components.allSatisfy({ $0 != "." && $0 != ".." }) else {
                throw ArchiveError.invalid("unsafe file path")
            }

            guard entry.localHeaderOffset + 30 <= archiveSize else {
                throw ArchiveError.invalid("local header extends beyond archive")
            }
            try input.seek(toOffset: entry.localHeaderOffset)
            let localHeader = try readExactly(input, count: 30)
            guard readUInt32(localHeader, at: 0) == 0x04034b50 else {
                throw ArchiveError.invalid("unexpected ZIP local header")
            }
            let localNameLength = UInt64(readUInt16(localHeader, at: 26))
            let localExtraLength = UInt64(readUInt16(localHeader, at: 28))
            let dataStart = entry.localHeaderOffset + 30 + localNameLength + localExtraLength
            guard dataStart <= archiveSize, entry.compressedSize <= archiveSize - dataStart else {
                throw ArchiveError.invalid("entry extends beyond the archive")
            }

            let (addedBytes, overflow) = extractedBytes.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, addedBytes <= maxExtractedBytes, entryCount < maxEntryCount else {
                throw ArchiveError.tooLarge(entry.name)
            }
            extractedBytes = addedBytes
            entryCount += 1

            let outputURL = components.reduce(destination) { $0.appendingPathComponent($1) }
            guard outputURL.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
                throw ArchiveError.invalid("unsafe file path")
            }

            if entry.name.hasSuffix("/") {
                try manager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                try manager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard manager.createFile(atPath: outputURL.path, contents: nil) else {
                    throw ArchiveError.invalid("could not create an extracted file")
                }
                try input.seek(toOffset: dataStart)
                let output = try FileHandle(forWritingTo: outputURL)
                defer { try? output.close() }
                if entry.method == 0 {
                    var remaining = entry.compressedSize
                    while remaining > 0 {
                        let count = Int(min(remaining, 1024 * 1024))
                        try output.write(contentsOf: readExactly(input, count: count))
                        remaining -= UInt64(count)
                    }
                } else {
                    try decompressDeflateEntry(
                        from: input,
                        compressedSize: entry.compressedSize,
                        expectedUncompressedSize: entry.uncompressedSize,
                        to: output
                    )
                }
                try output.synchronize()
                guard try crc32(of: outputURL) == entry.checksum else {
                    throw ArchiveError.invalid("checksum mismatch for \(entry.name)")
                }
            }
        }

        succeeded = true
    }

    private static func readCentralDirectory(
        from input: FileHandle,
        archiveSize: UInt64,
        maxEntryCount: Int
    ) throws -> [CentralDirectoryEntry] {
        guard archiveSize >= 22 else {
            throw ArchiveError.invalid("archive too small")
        }
        let searchWindow = Int(min(archiveSize, 65_557))
        let windowStart = archiveSize - UInt64(searchWindow)
        try input.seek(toOffset: windowStart)
        let tail = try readExactly(input, count: searchWindow)

        var eocdOffsetInTail: Int?
        for idx in stride(from: tail.count - 22, through: 0, by: -1) {
            if readUInt32(tail, at: idx) == 0x06054b50 {
                let commentLength = Int(readUInt16(tail, at: idx + 20))
                if idx + 22 + commentLength == tail.count {
                    eocdOffsetInTail = idx
                    break
                }
            }
        }
        guard let eocdIdx = eocdOffsetInTail else {
            throw ArchiveError.invalid("missing end of central directory")
        }

        let totalEntries = Int(readUInt16(tail, at: eocdIdx + 10))
        let centralSize = UInt64(readUInt32(tail, at: eocdIdx + 12))
        let centralOffset = UInt64(readUInt32(tail, at: eocdIdx + 16))
        guard centralOffset <= archiveSize, centralSize <= archiveSize - centralOffset else {
            throw ArchiveError.invalid("central directory extends beyond archive")
        }
        guard totalEntries <= maxEntryCount else {
            throw ArchiveError.tooLarge("archive")
        }

        try input.seek(toOffset: centralOffset)
        var entries: [CentralDirectoryEntry] = []
        entries.reserveCapacity(totalEntries)

        for _ in 0..<totalEntries {
            let record = try readExactly(input, count: 46)
            guard readUInt32(record, at: 0) == 0x02014b50 else {
                throw ArchiveError.invalid("unexpected central directory record")
            }
            let flags = readUInt16(record, at: 8)
            let method = readUInt16(record, at: 10)
            let checksum = readUInt32(record, at: 16)
            let compressedSize = UInt64(readUInt32(record, at: 20))
            let uncompressedSize = UInt64(readUInt32(record, at: 24))
            let nameLength = Int(readUInt16(record, at: 28))
            let extraLength = Int(readUInt16(record, at: 30))
            let commentLength = Int(readUInt16(record, at: 32))
            let localOffset = UInt64(readUInt32(record, at: 42))

            let nameData = try readExactly(input, count: nameLength)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ArchiveError.invalid("file name is not UTF-8")
            }
            let skipLen = UInt64(extraLength + commentLength)
            if skipLen > 0 {
                let current = try input.offset()
                try input.seek(toOffset: current + skipLen)
            }
            entries.append(CentralDirectoryEntry(
                name: name,
                flags: flags,
                method: method,
                checksum: checksum,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
        }
        return entries
    }

    private static func decompressDeflateEntry(
        from input: FileHandle,
        compressedSize: UInt64,
        expectedUncompressedSize: UInt64,
        to output: FileHandle
    ) throws {
        if compressedSize == 0 && expectedUncompressedSize == 0 {
            return
        }
        let sentinel = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { sentinel.deallocate() }
        var stream = compression_stream(dst_ptr: sentinel, dst_size: 0, src_ptr: sentinel, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw ArchiveError.invalid("unable to initialize deflate decoder")
        }
        defer { compression_stream_destroy(&stream) }

        let chunkSize = 64 * 1024
        var outBuffer = [UInt8](repeating: 0, count: chunkSize)
        var remaining = compressedSize
        var totalWritten: UInt64 = 0
        var inBuffer = Data()
        var inOffset = 0

        while true {
            if inOffset >= inBuffer.count && remaining > 0 {
                let toRead = Int(min(remaining, UInt64(chunkSize)))
                inBuffer = try readExactly(input, count: toRead)
                remaining -= UInt64(toRead)
                inOffset = 0
            }

            let processFlags: Int32 = (remaining == 0) ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status: compression_status = try inBuffer.withUnsafeBytes { rawIn -> compression_status in
                let inBase = rawIn.bindMemory(to: UInt8.self).baseAddress
                return try outBuffer.withUnsafeMutableBufferPointer { rawOut -> compression_status in
                    guard let outBase = rawOut.baseAddress else {
                        throw ArchiveError.invalid("output buffer allocation failed")
                    }
                    stream.src_ptr = inBase.map { $0.advanced(by: inOffset) } ?? UnsafePointer(sentinel)
                    stream.src_size = inBuffer.count - inOffset
                    stream.dst_ptr = outBase
                    stream.dst_size = chunkSize

                    let s = compression_stream_process(&stream, processFlags)
                    let consumed = (inBuffer.count - inOffset) - stream.src_size
                    inOffset += consumed
                    let produced = chunkSize - stream.dst_size
                    if produced > 0 {
                        totalWritten += UInt64(produced)
                        if totalWritten > expectedUncompressedSize + 1024 * 1024 {
                            throw ArchiveError.invalid("deflated output exceeds declared size")
                        }
                        try output.write(contentsOf: Data(rawOut[0..<produced]))
                    }
                    return s
                }
            }

            if status == COMPRESSION_STATUS_ERROR {
                throw ArchiveError.invalid("corrupt deflate stream")
            }
            if status == COMPRESSION_STATUS_END {
                break
            }
            if remaining == 0 && inOffset >= inBuffer.count && stream.dst_size > 0 {
                throw ArchiveError.invalid("unexpected end of deflate stream")
            }
        }

        if totalWritten != expectedUncompressedSize {
            throw ArchiveError.invalid("uncompressed size mismatch")
        }
    }

    private static func createEmptyFile(at url: URL) throws -> URL {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }

    private static func copy(_ source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1 != 0) ? ((crc >> 1) ^ 0xedb88320) : (crc >> 1) }
        }
        return ~crc
    }

    static func crc32(of data: Data) -> UInt32 {
        crc32(data)
    }

    static func crc32(of url: URL) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var crc: UInt32 = 0xffffffff
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            for byte in chunk { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) } }
        }
        return ~crc
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff)); data.append(UInt8(value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        appendUInt16(UInt16(value & 0xffff), to: &data)
        appendUInt16(UInt16(value >> 16), to: &data)
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw ArchiveError.invalid("file ended unexpectedly")
            }
            result.append(chunk)
        }
        return result
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(readUInt16(data, at: offset)) | (UInt32(readUInt16(data, at: offset + 2)) << 16)
    }
}
