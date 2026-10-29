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

        var errorDescription: String? {
            switch self {
            case .tooLarge(let name): "\(name) is too large to include in this ZIP archive."
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

    private static func crc32(of url: URL) throws -> UInt32 {
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
}
