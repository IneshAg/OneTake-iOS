import Foundation

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

    /// Extracts the store-only ZIPs produced by `write`. Paths are validated before writing so an
    /// imported archive cannot escape its staging directory.
    static func extract(from archiveURL: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: archiveURL)
        var succeeded = false
        defer {
            try? input.close()
            if !succeeded { try? manager.removeItem(at: destination) }
        }

        let archiveSize = UInt64((try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var extractedBytes: UInt64 = 0
        var entryCount = 0

        while true {
            guard let signatureData = try input.read(upToCount: 4), signatureData.count == 4 else { break }
            let signature = readUInt32(signatureData, at: 0)
            if signature == 0x02014b50 || signature == 0x06054b50 { break }
            guard signature == 0x04034b50 else { throw ArchiveError.invalid("unexpected ZIP record") }

            let rest = try readExactly(input, count: 26)
            let header = signatureData + rest
            let flags = readUInt16(header, at: 6)
            let method = readUInt16(header, at: 8)
            let checksum = readUInt32(header, at: 14)
            let compressedSize = UInt64(readUInt32(header, at: 18))
            let uncompressedSize = UInt64(readUInt32(header, at: 22))
            let nameLength = Int(readUInt16(header, at: 26))
            let extraLength = Int(readUInt16(header, at: 28))

            guard flags & 0x0001 == 0, flags & 0x0008 == 0 else {
                throw ArchiveError.unsupported("encrypted or streaming entries")
            }
            guard method == 0, compressedSize == uncompressedSize else {
                throw ArchiveError.unsupported("compressed entries")
            }
            let nameData = try readExactly(input, count: nameLength)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ArchiveError.invalid("file name is not UTF-8")
            }
            let components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !name.hasPrefix("/"), !name.contains("\\"), !components.isEmpty,
                  components.allSatisfy({ $0 != "." && $0 != ".." }) else {
                throw ArchiveError.invalid("unsafe file path")
            }

            let extraStart = try input.offset()
            try input.seek(toOffset: extraStart + UInt64(extraLength))
            let dataStart = try input.offset()
            guard dataStart <= archiveSize, compressedSize <= archiveSize - dataStart else {
                throw ArchiveError.invalid("entry extends beyond the archive")
            }
            extractedBytes += uncompressedSize
            guard extractedBytes <= 8 * 1024 * 1024 * 1024, entryCount < 20_000 else {
                throw ArchiveError.tooLarge(name)
            }
            entryCount += 1

            let outputURL = components.reduce(destination) { $0.appendingPathComponent($1) }
            let standardizedRoot = destination.standardizedFileURL.path + "/"
            guard outputURL.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
                throw ArchiveError.invalid("unsafe file path")
            }
            if name.hasSuffix("/") {
                try manager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                try manager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard manager.createFile(atPath: outputURL.path, contents: nil) else {
                    throw ArchiveError.invalid("could not create an extracted file")
                }
                let output = try FileHandle(forWritingTo: outputURL)
                defer { try? output.close() }
                var remaining = compressedSize
                while remaining > 0 {
                    let count = Int(min(remaining, 1024 * 1024))
                    try output.write(contentsOf: readExactly(input, count: count))
                    remaining -= UInt64(count)
                }
                try output.synchronize()
                guard try crc32(of: outputURL) == checksum else {
                    throw ArchiveError.invalid("checksum mismatch for \(name)")
                }
            }
            try input.seek(toOffset: dataStart + compressedSize)
        }

        guard entryCount > 0 else { throw ArchiveError.invalid("archive is empty") }
        succeeded = true
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
