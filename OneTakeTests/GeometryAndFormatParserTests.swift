import XCTest
import PDFKit
import UIKit
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
}
