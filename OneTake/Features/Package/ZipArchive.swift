import Foundation

enum ZipArchive {
    static func write(_ entries: [(String, Data)], to url: URL) throws {
        var body = Data()
        var central = Data()
        var offset: UInt32 = 0
        for (name, data) in entries {
            let nameData = Data(name.utf8)
            let checksum = crc32(data)
            appendUInt32(0x04034b50, to: &body)
            appendUInt16(20, to: &body)
            appendUInt16(0x0800, to: &body)
            appendUInt16(0, to: &body)
            appendUInt16(0, to: &body)
            appendUInt16(0, to: &body)
            appendUInt32(checksum, to: &body)
            appendUInt32(UInt32(data.count), to: &body)
            appendUInt32(UInt32(data.count), to: &body)
            appendUInt16(UInt16(nameData.count), to: &body)
            appendUInt16(0, to: &body)
            body.append(nameData)
            body.append(data)

            appendUInt32(0x02014b50, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(0x0800, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(checksum, to: &central)
            appendUInt32(UInt32(data.count), to: &central)
            appendUInt32(UInt32(data.count), to: &central)
            appendUInt16(UInt16(nameData.count), to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(0, to: &central)
            appendUInt32(offset, to: &central)
            central.append(nameData)
            offset = UInt32(body.count)
        }
        var archive = body
        archive.append(central)
        appendUInt32(0x06054b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt32(UInt32(central.count), to: &archive)
        appendUInt32(UInt32(body.count), to: &archive)
        appendUInt16(0, to: &archive)
        try archive.write(to: url, options: .atomic)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        appendUInt16(UInt16(value & 0xffff), to: &data)
        appendUInt16(UInt16(value >> 16), to: &data)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 &- (crc & 1)) }
        }
        return ~crc
    }
}
