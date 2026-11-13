import XCTest
import PDFKit
import UIKit
import Compression
import UniformTypeIdentifiers
@testable import OneTake

final class GeometryAndFormatParserTests: XCTestCase {

    private enum TestPDFFixture {
        static func makeTwoColumnPDF(
            leftLines: [String],
            rightLines: [String]
        ) throws -> URL {
            let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let data = renderer.pdfData { ctx in
                ctx.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.black
                ]
                let lineHeight: CGFloat = 22
                let startY: CGFloat = 90
                for (idx, line) in leftLines.enumerated() {
                    let rect = CGRect(x: 42, y: startY + CGFloat(idx) * lineHeight, width: 220, height: 18)
                    (line as NSString).draw(in: rect, withAttributes: attrs)
                }
                for (idx, line) in rightLines.enumerated() {
                    let rect = CGRect(x: 340, y: startY + CGFloat(idx) * lineHeight, width: 230, height: 18)
                    (line as NSString).draw(in: rect, withAttributes: attrs)
                }
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("two-col-\(UUID().uuidString).pdf")
            try data.write(to: url)
            return url
        }

        static func makeScreenplayPDF() throws -> URL {
            let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let data = renderer.pdfData { ctx in
                ctx.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                ("INT. DINER - NIGHT" as NSString).draw(
                    in: CGRect(x: 108, y: 90, width: 396, height: 18),
                    withAttributes: attrs
                )
                ("MAYA enters and looks around." as NSString).draw(
                    in: CGRect(x: 108, y: 122, width: 396, height: 18),
                    withAttributes: attrs
                )
                ("MAYA" as NSString).draw(
                    in: CGRect(x: 266, y: 158, width: 80, height: 18),
                    withAttributes: attrs
                )
                ("Are you still awake?" as NSString).draw(
                    in: CGRect(x: 180, y: 178, width: 252, height: 18),
                    withAttributes: attrs
                )
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("screenplay-\(UUID().uuidString).pdf")
            try data.write(to: url)
            return url
        }

        static func makeEncryptedPDF() throws -> URL {
            let plainURL = try makeTwoColumnPDF(leftLines: ["SECRET"], rightLines: ["FILE"])
            defer { try? FileManager.default.removeItem(at: plainURL) }
            let doc = try XCTUnwrap(PDFDocument(url: plainURL))
            let encryptedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("encrypted-\(UUID().uuidString).pdf")
            let wrote = doc.write(to: encryptedURL, withOptions: [
                .userPasswordOption: "pass123",
                .ownerPasswordOption: "owner123"
            ])
            XCTAssertTrue(wrote)
            return encryptedURL
        }
    }

    func testPDFGeometryExtractorSeparatesTwoColumnsCleanly() throws {
        let url = try TestPDFFixture.makeTwoColumnPDF(
            leftLines: ["VIDEO:", "Close-up on coffee cup"],
            rightLines: ["AUDIO:", "ANNOUNCER: Start fresh."]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let lines = PDFGeometryExtractor.extractLines(from: page, pageIndex: 0)
        let reconstructed = OCRLayoutReconstructor.reconstruct(layoutLines: lines)
        XCTAssertTrue(reconstructed.contains("VIDEO:\nClose-up on coffee cup"), "Reconstructed was:\n\(reconstructed)")
        XCTAssertTrue(reconstructed.contains("AUDIO:\nANNOUNCER: Start fresh."), "Reconstructed was:\n\(reconstructed)")
        XCTAssertFalse(reconstructed.contains("VIDEO: AUDIO:"), "Reconstructed was:\n\(reconstructed)")
    }

    func testPDFGeometryExtractorPreservesScreenplayIndentation() throws {
        let url = try TestPDFFixture.makeScreenplayPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let lines = PDFGeometryExtractor.extractLines(from: page, pageIndex: 0)
        let actionLine = try XCTUnwrap(lines.first { $0.text.contains("MAYA enters") })
        let dialogueLine = try XCTUnwrap(lines.first { $0.text.contains("Are you still awake?") })
        let cueLine = try XCTUnwrap(lines.first { $0.text.trimmingCharacters(in: .whitespaces) == "MAYA" })

        XCTAssertLessThan(actionLine.estimatedIndent, dialogueLine.estimatedIndent)
        XCTAssertLessThan(dialogueLine.estimatedIndent, cueLine.estimatedIndent)
        XCTAssertGreaterThan(actionLine.rect.midY, cueLine.rect.midY, "Vision Y=0 is bottom, Y=1 is top")
    }

    func testLayoutLineAndLayoutDocumentContract() {
        let rect = CGRect(x: 0.42, y: 0.72, width: 0.10, height: 0.02)
        let defaultIndentLine = LayoutLine(text: "MAYA", rect: rect, pageIndex: 0)
        XCTAssertEqual(defaultIndentLine.estimatedIndent, rect.minX, accuracy: 0.0001)

        let customIndentLine = LayoutLine(text: "MAYA", rect: rect, pageIndex: 0, estimatedIndent: 0.50)
        XCTAssertEqual(customIndentLine.estimatedIndent, 0.50, accuracy: 0.0001)
        XCTAssertNotEqual(defaultIndentLine, customIndentLine)

        let doc = LayoutDocument(pages: [[defaultIndentLine]])
        XCTAssertEqual(doc.reconstructedPages.count, 1)
        XCTAssertFalse(doc.fullText.isEmpty)
        XCTAssertEqual(doc, LayoutDocument(pages: [[defaultIndentLine]]))
    }

    func testExtractLayoutDocumentThrowsStructuredErrors() async throws {
        let encryptedURL = try TestPDFFixture.makeEncryptedPDF()
        defer { try? FileManager.default.removeItem(at: encryptedURL) }

        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: encryptedURL)
            XCTFail("Expected NoticeImportError.encryptedPDF")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .encryptedPDF)
        }

        let legacyEncrypted = await NoticeOCR.extractDocument(fromFileAt: encryptedURL)
        XCTAssertNil(legacyEncrypted)

        let corruptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).pdf")
        try Data("not a valid pdf".utf8).write(to: corruptURL)
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: corruptURL)
            XCTFail("Expected NoticeImportError.corruptDocument")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .corruptDocument)
        }

        let unsupportedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-\(UUID().uuidString).bin")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81]).write(to: unsupportedURL)
        defer { try? FileManager.default.removeItem(at: unsupportedURL) }

        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: unsupportedURL)
            XCTFail("Expected NoticeImportError.unsupportedFormat")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .unsupportedFormat)
        }
    }

    func testPDFGeometryExtractorPreservesSpacesInTightlyTrackedItalicProseAndWideLines() throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let tightItalicAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 6),
                .kern: -0.4,
                .foregroundColor: UIColor.black
            ]
            let longTightProse = "hello world from tightly tracked italic prose across the full page width"
            (longTightProse as NSString).draw(
                in: CGRect(x: 42, y: 80, width: 520, height: 14),
                withAttributes: tightItalicAttrs
            )

            let colAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            ("VIDEO: Wide left" as NSString).draw(
                in: CGRect(x: 42, y: 120, width: 200, height: 18),
                withAttributes: colAttrs
            )
            ("AUDIO: Wide right" as NSString).draw(
                in: CGRect(x: 340, y: 120, width: 220, height: 18),
                withAttributes: colAttrs
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tight-italic-\(UUID().uuidString).pdf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let lines = PDFGeometryExtractor.extractLines(from: page, pageIndex: 0)
        let joined = lines.map(\.text).joined(separator: "\n")

        XCTAssertTrue(
            joined.contains("hello world from tightly tracked italic prose across the full page width"),
            "Tightly tracked italic prose lost word spacing:\n\(joined)"
        )
        XCTAssertTrue(lines.contains { $0.text.contains("VIDEO: Wide left") && $0.rect.minX < 0.2 })
        XCTAssertTrue(lines.contains { $0.text.contains("AUDIO: Wide right") && $0.rect.minX > 0.45 })
    }

    func testExtractLayoutDocumentHandlesLatin1UTF16AndCorruptExtensionlessPDF() async throws {
        // 1. Extensionless ISO-Latin-1 text file
        let latin1Text = "Café Audition Notice for Noël"
        let latin1URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("latin1-notice-\(UUID().uuidString)")
        let latin1Data = try XCTUnwrap(latin1Text.data(using: .isoLatin1))
        try latin1Data.write(to: latin1URL)
        defer { try? FileManager.default.removeItem(at: latin1URL) }

        let latin1Doc = try await NoticeOCR.extractLayoutDocument(fromFileAt: latin1URL)
        XCTAssertTrue(latin1Doc.fullText.contains("Café Audition Notice for Noël"))

        // 2. Extensionless UTF-16 text file (with BOM)
        let utf16Text = "AUDITION NOTICE\nRole: Maya"
        let utf16URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("utf16-notice-\(UUID().uuidString)")
        let utf16Data = try XCTUnwrap(utf16Text.data(using: .utf16))
        try utf16Data.write(to: utf16URL)
        defer { try? FileManager.default.removeItem(at: utf16URL) }

        let utf16Doc = try await NoticeOCR.extractLayoutDocument(fromFileAt: utf16URL)
        XCTAssertTrue(utf16Doc.fullText.contains("Role: Maya"))

        // 3. Extensionless corrupt %PDF- file must throw .corruptDocument
        let corruptExtensionlessPDF = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-pdf-\(UUID().uuidString)")
        try Data("%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\ntruncated".utf8).write(to: corruptExtensionlessPDF)
        defer { try? FileManager.default.removeItem(at: corruptExtensionlessPDF) }

        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: corruptExtensionlessPDF)
            XCTFail("Expected NoticeImportError.corruptDocument for corrupt extensionless PDF")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .corruptDocument)
        }
    }

    func testFDXParserExtractsExactScenesAndDialogue() throws {
        let fdx = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. STUDIO - NIGHT</Text></Paragraph>
            <Paragraph Type="Action"><Text>Rain lashes the skylight.</Text></Paragraph>
            <Paragraph Type="Character"><Text>SANDY</Text></Paragraph>
            <Paragraph Type="Parenthetical"><Text>(softly)</Text></Paragraph>
            <Paragraph Type="Dialogue"><Text>Wait </Text><Text Style="Italic">for me.</Text></Paragraph>
            <Paragraph Type="Scene Heading"><Text>EXT. ALLEY - CONTINUOUS</Text></Paragraph>
            <Paragraph Type="Character"><Text>MARCUS (V.O.)</Text></Paragraph>
            <Paragraph Type="Dialogue"><Text>Too late.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """.data(using: .utf8)!

        let (scenes, doc) = try StructuredDocumentParsers.parseFDX(data: fdx)
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].heading, "INT. STUDIO - NIGHT")
        XCTAssertEqual(scenes[0].lines.first?.character, "SANDY")
        XCTAssertEqual(scenes[0].lines.first?.text, "Wait for me.")
        XCTAssertEqual(scenes[1].heading, "EXT. ALLEY - CONTINUOUS")
        XCTAssertEqual(scenes[1].lines.first?.character, "MARCUS")
        XCTAssertEqual(scenes[1].lines.first?.text, "Too late.")
        XCTAssertTrue(doc.fullText.contains("INT. STUDIO - NIGHT"))
        XCTAssertTrue(doc.fullText.contains("(softly)"))

        let allLines = doc.pages.flatMap { $0 }
        let headingLine = try XCTUnwrap(allLines.first { $0.text.contains("INT. STUDIO - NIGHT") })
        let cueLine = try XCTUnwrap(allLines.first { $0.text == "SANDY" })
        let dialogueLine = try XCTUnwrap(allLines.first { $0.text.contains("Wait for me.") })
        XCTAssertLessThan(headingLine.estimatedIndent, dialogueLine.estimatedIndent)
        XCTAssertLessThan(dialogueLine.estimatedIndent, cueLine.estimatedIndent)
    }

    func testFountainParserHandlesSluglinesForcedCuesAndDualDialogue() throws {
        let fountain = """
        Title: Night Shift
        Author: Jane Doe

        INT. PRECINCT - NIGHT

        Glass crunches underfoot.

        @McLane
        (breathless)
        Drop the radio now.

        .ROOFTOP - LATER

        HANS ^
        Don't move!

        @McLane ^
        I wasn't planning on it.
        """

        let (scenes, doc) = StructuredDocumentParsers.parseFountain(text: fountain)
        XCTAssertEqual(scenes.count, 2)
        XCTAssertEqual(scenes[0].heading, "INT. PRECINCT - NIGHT")
        XCTAssertEqual(scenes[0].lines.count, 1)
        XCTAssertEqual(scenes[0].lines[0].character, "McLane")
        XCTAssertEqual(scenes[0].lines[0].text, "Drop the radio now.")

        XCTAssertEqual(scenes[1].heading, "ROOFTOP - LATER")
        XCTAssertEqual(scenes[1].lines.count, 2)
        XCTAssertEqual(scenes[1].lines[0].character, "HANS")
        XCTAssertEqual(scenes[1].lines[0].text, "Don't move!")
        XCTAssertEqual(scenes[1].lines[1].character, "McLane")
        XCTAssertEqual(scenes[1].lines[1].text, "I wasn't planning on it.")
        XCTAssertTrue(doc.fullText.contains("INT. PRECINCT - NIGHT"))

        let allLines = doc.pages.flatMap { $0 }
        let cueLine = try XCTUnwrap(allLines.first { $0.text == "McLane" })
        let dialogueLine = try XCTUnwrap(allLines.first { $0.text == "Drop the radio now." })
        XCTAssertLessThan(dialogueLine.estimatedIndent, cueLine.estimatedIndent)
    }

    func testDOCXAndStructuredFormatsThroughNoticeOCRExtractLayoutDocument() async throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:pPr><w:ind w:left="0"/></w:pPr>
              <w:r><w:t>INT. CAFE - DAY</w:t></w:r>
            </w:p>
            <w:p>
              <w:pPr><w:ind w:left="3600"/></w:pPr>
              <w:r><w:t>MAYA</w:t></w:r>
            </w:p>
            <w:p>
              <w:pPr><w:ind w:left="1440"/></w:pPr>
              <w:r><w:t>Coffee is getting cold.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let docxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sides-\(UUID().uuidString).docx")
        try ZipArchive.write([
            ("[Content_Types].xml", Data("<Types/>".utf8)),
            ("word/document.xml", Data(documentXML.utf8))
        ], to: docxURL)
        defer { try? FileManager.default.removeItem(at: docxURL) }

        let docxDoc = try await NoticeOCR.extractLayoutDocument(fromFileAt: docxURL)
        XCTAssertTrue(docxDoc.fullText.contains("INT. CAFE - DAY"))
        XCTAssertTrue(docxDoc.fullText.contains("Coffee is getting cold."))
        let docxLines = docxDoc.pages.flatMap { $0 }
        let headingLine = try XCTUnwrap(docxLines.first { $0.text == "INT. CAFE - DAY" })
        let dialogueLine = try XCTUnwrap(docxLines.first { $0.text == "Coffee is getting cold." })
        let cueLine = try XCTUnwrap(docxLines.first { $0.text == "MAYA" })
        XCTAssertLessThan(headingLine.estimatedIndent, dialogueLine.estimatedIndent)
        XCTAssertLessThan(dialogueLine.estimatedIndent, cueLine.estimatedIndent)

        let fountainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sides-\(UUID().uuidString).fountain")
        try Data("INT. OFFICE - DAY\n\n@McLane\nCheck the files.".utf8).write(to: fountainURL)
        defer { try? FileManager.default.removeItem(at: fountainURL) }
        let fountainDoc = try await NoticeOCR.extractLayoutDocument(fromFileAt: fountainURL)
        XCTAssertTrue(fountainDoc.fullText.contains("Check the files."))
        let fountainSync = { NoticeOCR.extractText(fromFileAt: fountainURL) }()
        XCTAssertTrue(fountainSync?.contains("Check the files.") == true)
        let fountainAsync = await NoticeOCR.extractText(fromFileAt: fountainURL)
        XCTAssertTrue(fountainAsync?.contains("Check the files.") == true)

        XCTAssertTrue(NoticeOCR.supportedImportContentTypes.contains(where: { $0.preferredFilenameExtension == "fdx" }))
        XCTAssertTrue(NoticeOCR.supportedImportContentTypes.contains(where: { $0.preferredFilenameExtension == "fountain" }))
        XCTAssertTrue(NoticeOCR.supportedImportContentTypes.contains(where: { $0.preferredFilenameExtension == "docx" }))

        let fdxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sides-\(UUID().uuidString).fdx")
        try Data("""
        <?xml version="1.0" encoding="UTF-8" ?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. LAB - NIGHT</Text></Paragraph>
            <Paragraph Type="Character"><Text>ELENA</Text></Paragraph>
            <Paragraph Type="Dialogue"><Text>We are out of time.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """.utf8).write(to: fdxURL)
        defer { try? FileManager.default.removeItem(at: fdxURL) }
        let fdxDoc = try await NoticeOCR.extractLayoutDocument(fromFileAt: fdxURL)
        XCTAssertTrue(fdxDoc.fullText.contains("We are out of time."))
    }

    func testCorruptDocxOrFDXThrowsStructuredError() async throws {
        let corruptDocxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).docx")
        try Data("not-a-zip".utf8).write(to: corruptDocxURL)
        defer { try? FileManager.default.removeItem(at: corruptDocxURL) }
        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: corruptDocxURL)
            XCTFail("Expected NoticeImportError.corruptDocument for corrupt .docx")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .corruptDocument)
        }

        let corruptFDXURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).fdx")
        try Data("<FinalDraft><Content><Paragraph".utf8).write(to: corruptFDXURL)
        defer { try? FileManager.default.removeItem(at: corruptFDXURL) }
        do {
            _ = try await NoticeOCR.extractLayoutDocument(fromFileAt: corruptFDXURL)
            XCTFail("Expected NoticeImportError.corruptDocument for corrupt .fdx")
        } catch let error as NoticeImportError {
            XCTAssertEqual(error, .corruptDocument)
        }
    }

    func testDeflateCompressedDOCXExtraction() async throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>EXT. HARBOR - DAWN</w:t></w:r></w:p>
            <w:p><w:pPr><w:ind w:left="3600"/></w:pPr><w:r><w:t>CAPTAIN</w:t></w:r></w:p>
            <w:p><w:pPr><w:ind w:left="1440"/></w:pPr><w:r><w:t>All hands on deck before the tide turns.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """.utf8)

        let deflatedData: Data = xml.withUnsafeBytes { rawIn -> Data in
            let src = rawIn.bindMemory(to: UInt8.self).baseAddress!
            var dst = [UInt8](repeating: 0, count: xml.count + 256)
            let compressedCount = compression_encode_buffer(&dst, dst.count, src, xml.count, nil, COMPRESSION_ZLIB)
            return Data(dst.prefix(compressedCount))
        }
        XCTAssertGreaterThan(deflatedData.count, 0)

        let entryName = Data("word/document.xml".utf8)
        let crc = ZipArchive.crc32(xml)

        func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
        func le32(_ v: UInt32) -> Data {
            Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
        }

        var archive = Data()
        // Local header with data descriptor flag (0x0008) and zeroed sizes, like streaming Word/Java writers
        archive.append(le32(0x04034b50))
        archive.append(le16(20))
        archive.append(le16(0x0808)) // UTF-8 + data descriptor
        archive.append(le16(8))      // Deflate
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le32(0))
        archive.append(le32(0))
        archive.append(le32(0))
        archive.append(le16(UInt16(entryName.count)))
        archive.append(le16(0))
        archive.append(entryName)
        archive.append(deflatedData)

        let centralStart = UInt32(archive.count)
        archive.append(le32(0x02014b50))
        archive.append(le16(20))
        archive.append(le16(20))
        archive.append(le16(0x0808))
        archive.append(le16(8))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le32(crc))
        archive.append(le32(UInt32(deflatedData.count)))
        archive.append(le32(UInt32(xml.count)))
        archive.append(le16(UInt16(entryName.count)))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le32(0))
        archive.append(le32(0)) // local header offset
        archive.append(entryName)

        let centralSize = UInt32(archive.count) - centralStart
        archive.append(le32(0x06054b50))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(1))
        archive.append(le16(1))
        archive.append(le32(centralSize))
        archive.append(le32(centralStart))
        archive.append(le16(0))

        let docxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deflated-\(UUID().uuidString).docx")
        try archive.write(to: docxURL)
        defer { try? FileManager.default.removeItem(at: docxURL) }

        let doc = try await NoticeOCR.extractLayoutDocument(fromFileAt: docxURL)
        XCTAssertTrue(doc.fullText.contains("EXT. HARBOR - DAWN"))
        XCTAssertTrue(doc.fullText.contains("All hands on deck before the tide turns."))
    }
}
