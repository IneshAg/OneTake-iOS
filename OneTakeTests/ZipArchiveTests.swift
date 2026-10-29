import XCTest
@testable import OneTake

final class ZipArchiveTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ZipArchiveTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Header Signatures

    func testPKZIPHeaderSignatures() throws {
        let zipURL = tempDirectory.appendingPathComponent("signatures.zip")
        let entry1Data = Data("First entry payload".utf8)
        let entry2Data = Data("Second entry payload".utf8)
        let entries = [
            ("file1.txt", entry1Data),
            ("nested/file2.txt", entry2Data)
        ]

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)
        XCTAssertGreaterThan(archiveData.count, 0)

        // Local header 1 signature: 0x04034b50 (PK\x03\x04) in little-endian [0x50, 0x4B, 0x03, 0x04]
        let localSig1 = readUInt32(from: archiveData, at: 0)
        XCTAssertEqual(localSig1, 0x04034b50, "First local file header must have signature 0x04034b50")

        // Parse through first entry to find second local header
        let nameLen1 = Int(readUInt16(from: archiveData, at: 26))
        let extraLen1 = Int(readUInt16(from: archiveData, at: 28))
        let nextLocalOffset = 30 + nameLen1 + extraLen1 + entry1Data.count

        let localSig2 = readUInt32(from: archiveData, at: nextLocalOffset)
        XCTAssertEqual(localSig2, 0x04034b50, "Second local file header must have signature 0x04034b50")

        // Parse second entry to find central directory start
        let nameLen2 = Int(readUInt16(from: archiveData, at: nextLocalOffset + 26))
        let extraLen2 = Int(readUInt16(from: archiveData, at: nextLocalOffset + 28))
        let centralDirOffset = nextLocalOffset + 30 + nameLen2 + extraLen2 + entry2Data.count

        // Central directory header signature: 0x02014b50 (PK\x01\x02) in little-endian [0x50, 0x4B, 0x01, 0x02]
        let centralSig1 = readUInt32(from: archiveData, at: centralDirOffset)
        XCTAssertEqual(centralSig1, 0x02014b50, "First central directory header must have signature 0x02014b50")

        // Find End of Central Directory record by scanning backwards from end for 0x06054b50
        let eocdOffset = try findEOCDOffset(in: archiveData)
        let eocdSig = readUInt32(from: archiveData, at: eocdOffset)
        XCTAssertEqual(eocdSig, 0x06054b50, "End of Central Directory record must have signature 0x06054b50")
    }

    // MARK: - CRC-32 Accuracy

    func testIEEE8023CRC32Accuracy() throws {
        // Standard test vectors according to ISO 3309 / ITU-T V.42 / IEEE 802.3
        let standardVector = Data("123456789".utf8)
        let standardCRC = ZipArchive.crc32(standardVector)
        XCTAssertEqual(standardCRC, 0xcbf43926, "CRC-32 for '123456789' must match IEEE 802.3 test vector 0xcbf43926")

        let emptyVector = Data()
        let emptyCRC = ZipArchive.crc32(emptyVector)
        XCTAssertEqual(emptyCRC, 0x00000000, "CRC-32 for empty data must be 0x00000000")

        let foxVector = Data("The quick brown fox jumps over the lazy dog".utf8)
        let foxCRC = ZipArchive.crc32(foxVector)
        XCTAssertEqual(foxCRC, 0x414fa339, "CRC-32 for standard pangram must match 0x414fa339")

        // Verify the CRC is correctly serialized into the PKZIP local header and central header
        let zipURL = tempDirectory.appendingPathComponent("crc_test.zip")
        try ZipArchive.write([("fox.txt", foxVector)], to: zipURL)
        let zipData = try Data(contentsOf: zipURL)

        let localHeaderCRC = readUInt32(from: zipData, at: 14)
        XCTAssertEqual(localHeaderCRC, 0x414fa339, "Local file header CRC must match computed CRC-32")

        let nameLen = Int(readUInt16(from: zipData, at: 26))
        let centralOffset = 30 + nameLen + foxVector.count
        let centralHeaderCRC = readUInt32(from: zipData, at: centralOffset + 16)
        XCTAssertEqual(centralHeaderCRC, 0x414fa339, "Central directory header CRC must match computed CRC-32")
    }

    // MARK: - Multi-File Archive Generation

    func testMultiFileArchiveGeneration() throws {
        let zipURL = tempDirectory.appendingPathComponent("multi_file.zip")
        let entries: [(String, Data)] = [
            ("Videos/Slate.mov", Data(repeating: 0xAA, count: 512)),
            ("Videos/Scene_1_-_Take_1.mov", Data(repeating: 0xBB, count: 1024)),
            ("Headshots/primary.jpg", Data(repeating: 0xCC, count: 256)),
            ("Headshots/left45.jpg", Data(repeating: 0xDD, count: 128))
        ]

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        let eocdOffset = try findEOCDOffset(in: archiveData)
        let diskEntries = readUInt16(from: archiveData, at: eocdOffset + 8)
        let totalEntries = readUInt16(from: archiveData, at: eocdOffset + 10)
        let centralDirSize = readUInt32(from: archiveData, at: eocdOffset + 12)
        let centralDirOffset = readUInt32(from: archiveData, at: eocdOffset + 16)

        XCTAssertEqual(diskEntries, UInt16(entries.count), "EOCD disk entries must equal entry count")
        XCTAssertEqual(totalEntries, UInt16(entries.count), "EOCD total entries must equal entry count")
        XCTAssertGreaterThan(centralDirSize, 0, "Central directory size must be non-zero")
        XCTAssertGreaterThan(centralDirOffset, 0, "Central directory offset must be after local file bodies")

        // Traverse central directory headers and verify names
        var cursor = Int(centralDirOffset)
        for (expectedName, expectedData) in entries {
            let sig = readUInt32(from: archiveData, at: cursor)
            XCTAssertEqual(sig, 0x02014b50, "Header at offset \(cursor) must be central directory header")

            let crc = readUInt32(from: archiveData, at: cursor + 16)
            let compSize = readUInt32(from: archiveData, at: cursor + 20)
            let uncompSize = readUInt32(from: archiveData, at: cursor + 24)
            let nameLen = Int(readUInt16(from: archiveData, at: cursor + 28))
            let extraLen = Int(readUInt16(from: archiveData, at: cursor + 30))
            let commentLen = Int(readUInt16(from: archiveData, at: cursor + 32))

            let nameData = archiveData.subdata(in: (cursor + 46)..<(cursor + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)

            XCTAssertEqual(name, expectedName)
            XCTAssertEqual(compSize, UInt32(expectedData.count))
            XCTAssertEqual(uncompSize, UInt32(expectedData.count))
            XCTAssertEqual(crc, ZipArchive.crc32(expectedData))

            cursor += 46 + nameLen + extraLen + commentLen
        }
    }

    // MARK: - Zero-Length Entries

    func testZeroLengthEntries() throws {
        let zipURL = tempDirectory.appendingPathComponent("empty_entry.zip")
        let emptyData = Data()
        try ZipArchive.write([("empty.txt", emptyData)], to: zipURL)

        let archiveData = try Data(contentsOf: zipURL)
        let localSig = readUInt32(from: archiveData, at: 0)
        XCTAssertEqual(localSig, 0x04034b50)

        let crc = readUInt32(from: archiveData, at: 14)
        let compSize = readUInt32(from: archiveData, at: 18)
        let uncompSize = readUInt32(from: archiveData, at: 22)

        XCTAssertEqual(crc, 0x00000000, "Zero-length entry must have CRC 0")
        XCTAssertEqual(compSize, 0, "Zero-length entry compressed size must be 0")
        XCTAssertEqual(uncompSize, 0, "Zero-length entry uncompressed size must be 0")
    }

    // MARK: - Binary Data Fidelity

    func testBinaryDataFidelity() throws {
        let zipURL = tempDirectory.appendingPathComponent("binary_fidelity.zip")
        // Generate 2048 non-trivial pseudo-random bytes
        var binaryPayload = Data(count: 2048)
        for i in 0..<binaryPayload.count {
            binaryPayload[i] = UInt8((i * 37 + 101) & 0xFF)
        }

        try ZipArchive.write([("binary.bin", binaryPayload)], to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)

        let nameLen = Int(readUInt16(from: archiveData, at: 26))
        let extraLen = Int(readUInt16(from: archiveData, at: 28))
        let payloadStart = 30 + nameLen + extraLen
        let extractedPayload = archiveData.subdata(in: payloadStart..<(payloadStart + binaryPayload.count))

        XCTAssertEqual(extractedPayload, binaryPayload, "Payload read from zip must match byte-for-byte")
    }

    // MARK: - Empirical Boundary & Adversarial Stress Tests

    func testEmptyEntryList() throws {
        let zipURL = tempDirectory.appendingPathComponent("empty_list.zip")
        let emptyEntries: [(name: String, data: Data)] = []
        try ZipArchive.write(emptyEntries, to: zipURL)

        let archiveData = try Data(contentsOf: zipURL)
        XCTAssertEqual(archiveData.count, 22, "Empty archive must contain strictly the 22-byte EOCD record")

        let eocdSig = readUInt32(from: archiveData, at: 0)
        XCTAssertEqual(eocdSig, 0x06054b50, "EOCD signature must be 0x06054b50")

        let diskNumber = readUInt16(from: archiveData, at: 4)
        let cdDisk = readUInt16(from: archiveData, at: 6)
        let diskEntries = readUInt16(from: archiveData, at: 8)
        let totalEntries = readUInt16(from: archiveData, at: 10)
        let cdSize = readUInt32(from: archiveData, at: 12)
        let cdOffset = readUInt32(from: archiveData, at: 16)
        let commentLen = readUInt16(from: archiveData, at: 20)

        XCTAssertEqual(diskNumber, 0)
        XCTAssertEqual(cdDisk, 0)
        XCTAssertEqual(diskEntries, 0)
        XCTAssertEqual(totalEntries, 0)
        XCTAssertEqual(cdSize, 0)
        XCTAssertEqual(cdOffset, 0)
        XCTAssertEqual(commentLen, 0)

        // Persist copy in Exports directory for host-side unzip validation
        let exportsURL = MediaStore.directory("Exports").appendingPathComponent("stress_empty.zip")
        try? archiveData.write(to: exportsURL)
    }

    func testMultiMegabytePayloads() throws {
        let zipURL = tempDirectory.appendingPathComponent("multimb.zip")

        // 5 MB payload
        var mb5 = Data(count: 5 * 1024 * 1024)
        for i in 0..<mb5.count {
            mb5[i] = UInt8((i * 47 + 103) & 0xFF)
        }

        // 2 MB payload
        var mb2 = Data(count: 2 * 1024 * 1024)
        for i in 0..<mb2.count {
            mb2[i] = UInt8((i * 73 + 19) & 0xFF)
        }

        let entries: [(name: String, data: Data)] = [
            ("Videos/Scene_1_5MB.mov", mb5),
            ("Videos/Scene_2_2MB.mov", mb2)
        ]

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)
        XCTAssertGreaterThan(archiveData.count, 7 * 1024 * 1024, "Archive should exceed 7 megabytes")

        // Validate local header 1
        let sig1 = readUInt32(from: archiveData, at: 0)
        XCTAssertEqual(sig1, 0x04034b50)
        let crc1 = readUInt32(from: archiveData, at: 14)
        let compSize1 = readUInt32(from: archiveData, at: 18)
        let uncompSize1 = readUInt32(from: archiveData, at: 22)
        let nameLen1 = Int(readUInt16(from: archiveData, at: 26))
        let extraLen1 = Int(readUInt16(from: archiveData, at: 28))

        XCTAssertEqual(crc1, ZipArchive.crc32(mb5))
        XCTAssertEqual(compSize1, UInt32(mb5.count))
        XCTAssertEqual(uncompSize1, UInt32(mb5.count))

        let payload1Start = 30 + nameLen1 + extraLen1
        let extracted1 = archiveData.subdata(in: payload1Start..<(payload1Start + mb5.count))
        XCTAssertEqual(extracted1, mb5, "Extracted 5MB payload must match byte-for-byte")

        // Validate local header 2
        let offset2 = payload1Start + mb5.count
        let sig2 = readUInt32(from: archiveData, at: offset2)
        XCTAssertEqual(sig2, 0x04034b50)
        let crc2 = readUInt32(from: archiveData, at: offset2 + 14)
        let compSize2 = readUInt32(from: archiveData, at: offset2 + 18)
        let uncompSize2 = readUInt32(from: archiveData, at: offset2 + 22)
        let nameLen2 = Int(readUInt16(from: archiveData, at: offset2 + 26))
        let extraLen2 = Int(readUInt16(from: archiveData, at: offset2 + 28))

        XCTAssertEqual(crc2, ZipArchive.crc32(mb2))
        XCTAssertEqual(compSize2, UInt32(mb2.count))
        XCTAssertEqual(uncompSize2, UInt32(mb2.count))

        let payload2Start = offset2 + 30 + nameLen2 + extraLen2
        let extracted2 = archiveData.subdata(in: payload2Start..<(payload2Start + mb2.count))
        XCTAssertEqual(extracted2, mb2, "Extracted 2MB payload must match byte-for-byte")

        // Persist copy in Exports directory for host-side unzip validation
        let exportsURL = MediaStore.directory("Exports").appendingPathComponent("stress_multimb.zip")
        try? archiveData.write(to: exportsURL)
    }

    func testUnicodeAndEmojiFilenames() throws {
        let zipURL = tempDirectory.appendingPathComponent("unicode.zip")
        let entries: [(name: String, data: Data)] = [
            ("Videos/🎬_Slate_01.mov", Data("Emoji slate data".utf8)),
            ("Videos/オーディション_テイク1.mov", Data("Japanese audition data".utf8)),
            ("Videos/Élodie_René_Café.mov", Data("Accented characters data".utf8)),
            ("Headshots/Актёр_front.jpg", Data("Cyrillic actor data".utf8)),
            ("Videos/Take & Cut (Final) [1080p] #1 + Slate.mov", Data("Special symbols data".utf8))
        ]

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)

        // Verify UTF-8 language encoding flag (bit 11 = 0x0800) in all local headers
        var cursor = 0
        for (name, data) in entries {
            let sig = readUInt32(from: archiveData, at: cursor)
            XCTAssertEqual(sig, 0x04034b50, "Local header signature for \(name)")

            let flag = readUInt16(from: archiveData, at: cursor + 6)
            XCTAssertEqual(flag & 0x0800, 0x0800, "UTF-8 language encoding flag (bit 11) must be set in local header for \(name)")

            let nameLen = Int(readUInt16(from: archiveData, at: cursor + 26))
            let extraLen = Int(readUInt16(from: archiveData, at: cursor + 28))
            let nameData = archiveData.subdata(in: (cursor + 30)..<(cursor + 30 + nameLen))
            let decodedName = String(decoding: nameData, as: UTF8.self)
            XCTAssertEqual(decodedName, name, "Local header filename must decode properly from UTF-8")

            cursor += 30 + nameLen + extraLen + data.count
        }

        // Verify central directory headers
        let eocdOffset = try findEOCDOffset(in: archiveData)
        let cdOffset = Int(readUInt32(from: archiveData, at: eocdOffset + 16))
        var cdCursor = cdOffset
        for (name, data) in entries {
            let cdSig = readUInt32(from: archiveData, at: cdCursor)
            XCTAssertEqual(cdSig, 0x02014b50, "Central directory header signature for \(name)")

            let cdFlag = readUInt16(from: archiveData, at: cdCursor + 8)
            XCTAssertEqual(cdFlag & 0x0800, 0x0800, "UTF-8 flag must be set in central directory header for \(name)")

            let nameLen = Int(readUInt16(from: archiveData, at: cdCursor + 28))
            let extraLen = Int(readUInt16(from: archiveData, at: cdCursor + 30))
            let commentLen = Int(readUInt16(from: archiveData, at: cdCursor + 32))

            let cdNameData = archiveData.subdata(in: (cdCursor + 46)..<(cdCursor + 46 + nameLen))
            let decodedCDName = String(decoding: cdNameData, as: UTF8.self)
            XCTAssertEqual(decodedCDName, name, "Central directory filename must decode properly from UTF-8")

            cdCursor += 46 + nameLen + extraLen + commentLen
        }

        // Persist copy in Exports directory for host-side unzip validation
        let exportsURL = MediaStore.directory("Exports").appendingPathComponent("stress_unicode.zip")
        try? archiveData.write(to: exportsURL)
    }

    func testDeepAndLongPaths() throws {
        let zipURL = tempDirectory.appendingPathComponent("deep.zip")
        let deepPath = "a/b/c/d/e/f/g/h/i/j/deep_clip.mov"
        let longPath = "Videos/" + String(repeating: "scene_take_segment_", count: 10) + ".mov"

        let deepData = Data("Deep path payload".utf8)
        let longData = Data("Long filename payload".utf8)

        let entries: [(name: String, data: Data)] = [
            (deepPath, deepData),
            (longPath, longData)
        ]

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)
        XCTAssertGreaterThan(archiveData.count, 0)

        let eocdOffset = try findEOCDOffset(in: archiveData)
        let totalEntries = readUInt16(from: archiveData, at: eocdOffset + 10)
        XCTAssertEqual(totalEntries, 2)

        // Persist copy in Exports directory for host-side unzip validation
        let exportsURL = MediaStore.directory("Exports").appendingPathComponent("stress_deep.zip")
        try? archiveData.write(to: exportsURL)
    }

    func testDifferentialCRC32AgainstPythonVectors() {
        // ITU-T V.42 / ISO 3309 standard vectors
        XCTAssertEqual(ZipArchive.crc32(Data("a".utf8)), 0xe8b7be43)
        XCTAssertEqual(ZipArchive.crc32(Data("abc".utf8)), 0x352441c2)
        XCTAssertEqual(ZipArchive.crc32(Data("message digest".utf8)), 0x20159d7f)

        // 256 sequential bytes 0...255 -> Python zlib.crc32: 0x29058c73
        var allBytes = Data(count: 256)
        for i in 0..<256 { allBytes[i] = UInt8(i) }
        XCTAssertEqual(ZipArchive.crc32(allBytes), 0x29058c73, "All 256 sequential bytes must match Python zlib.crc32 0x29058c73")

        // 1024 zero bytes -> Python zlib.crc32: 0xefb5af2e
        let zeros = Data(repeating: 0x00, count: 1024)
        XCTAssertEqual(ZipArchive.crc32(zeros), 0xefb5af2e, "1024 zeros must match Python zlib.crc32 0xefb5af2e")

        // 1024 0xFF bytes -> Python zlib.crc32: 0xb83afff4
        let ones = Data(repeating: 0xff, count: 1024)
        XCTAssertEqual(ZipArchive.crc32(ones), 0xb83afff4, "1024 0xFFs must match Python zlib.crc32 0xb83afff4")

        // 64 KB pattern -> Python zlib.crc32: 0x2c51f591
        var pattern64K = Data(count: 65536)
        for i in 0..<pattern64K.count { pattern64K[i] = UInt8((i * 37 + 101) & 0xFF) }
        XCTAssertEqual(ZipArchive.crc32(pattern64K), 0x2c51f591, "64KB pattern must match Python zlib.crc32 0x2c51f591")

        // 1 MB pattern -> Python zlib.crc32: 0x290b499f
        var pattern1M = Data(count: 1048576)
        for i in 0..<pattern1M.count { pattern1M[i] = UInt8((i * 47 + 103) & 0xFF) }
        XCTAssertEqual(ZipArchive.crc32(pattern1M), 0x290b499f, "1MB pattern must match Python zlib.crc32 0x290b499f")
    }

    func testStress100Entries() throws {
        let zipURL = tempDirectory.appendingPathComponent("stress_100.zip")
        var entries: [(name: String, data: Data)] = []
        for i in 1...100 {
            let size = (i * 29) % 2048
            var data = Data(count: size)
            for b in 0..<size { data[b] = UInt8((b + i) & 0xFF) }
            entries.append(("Category_\(i % 5)/file_\(i).dat", data))
        }

        try ZipArchive.write(entries, to: zipURL)
        let archiveData = try Data(contentsOf: zipURL)
        let eocdOffset = try findEOCDOffset(in: archiveData)

        let diskEntries = readUInt16(from: archiveData, at: eocdOffset + 8)
        let totalEntries = readUInt16(from: archiveData, at: eocdOffset + 10)
        XCTAssertEqual(diskEntries, 100)
        XCTAssertEqual(totalEntries, 100)

        // Persist copy in Exports directory for host-side unzip validation
        let exportsURL = MediaStore.directory("Exports").appendingPathComponent("stress_100.zip")
        try? archiveData.write(to: exportsURL)
    }

    // MARK: - Private Helpers

    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private func findEOCDOffset(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            XCTFail("Data too short for EOCD")
            return 0
        }
        for i in stride(from: data.count - 22, through: 0, by: -1) {
            if readUInt32(from: data, at: i) == 0x06054b50 {
                return i
            }
        }
        XCTFail("EOCD signature 0x06054b50 not found")
        return 0
    }
}
