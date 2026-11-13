import XCTest
import PDFKit
@testable import OneTake

final class RealPDFParserTests: XCTestCase {

    private func resolvePDFURL(named resourceName: String, fileExtension: String = "pdf") -> URL? {
        let bundle = Bundle(for: RealPDFParserTests.self)
        if let url = bundle.url(forResource: resourceName, withExtension: fileExtension),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("\(resourceName).\(fileExtension)")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    private func auditPDF(named resourceName: String) async throws -> (doc: NoticeOCR.ExtractedDocument, draft: NoticeParser.Draft) {
        guard let url = resolvePDFURL(named: resourceName) else {
            XCTFail("\(resourceName).pdf not found in bundle or project root")
            throw NSError(domain: "RealPDFParserTests", code: 404)
        }

        guard let doc = await NoticeOCR.extractDocument(fromFileAt: url) else {
            XCTFail("NoticeOCR.extractDocument returned nil for \(resourceName).pdf")
            throw NSError(domain: "RealPDFParserTests", code: 500)
        }

        XCTAssertTrue(NoticeOCR.looksReadable(doc.fullText), "\(resourceName).pdf extracted text must pass looksReadable")
        XCTAssertFalse(doc.pages.isEmpty, "\(resourceName).pdf must produce non-empty pages")

        let draft = await NoticeParser.parseAsync(
            doc.fullText,
            pages: doc.pages,
            sourceDocuments: [AuditionSource(name: url.lastPathComponent, kind: .castingNotice, url: url, pageCount: doc.pageCount)]
        )

        print("==========================================")
        print("PDF AUDIT: \(resourceName).pdf")
        print("pageCount: \(doc.pageCount) | fullText chars: \(doc.fullText.count)")
        print("--- PARSED DRAFT ---")
        print("project: '\(draft.project)' | projectType: '\(draft.projectType)'")
        print("role: '\(draft.role)' | roleSize: '\(draft.roleSize)'")
        print("candidateRoles (\(draft.candidateRoles.count)): \(draft.candidateRoles)")
        print("castingOffice: '\(draft.castingOffice)'")
        print("isNoticeOnly: \(NoticeParser.isNoticeOnly(doc.fullText)) | hasSides: \(draft.hasSides)")
        print("availablePortions (\(draft.availablePortions.count)): \(draft.availablePortions.map { "\($0.displayTitle) [chars:\($0.characters.joined(separator: ","))]" })")
        print("asks: \(draft.asks)")
        print("destination: \(draft.destination.rawValue) | detail: '\(draft.destinationDetail ?? "nil")' | detected: \(draft.destinationWasDetected)")
        print("includeSlate: \(draft.includeSlate) | includeHeadshots: \(draft.includeHeadshots)")
        print("missingRequiredDetails: \(draft.missingRequiredDetails)")

        let fallbackRole = draft.candidateRoles.first ?? draft.role
        if !fallbackRole.isEmpty {
            let scenes = ScriptParser.parseScenes(from: doc.fullText, myRole: fallbackRole)
            print("ScriptParser scenes for '\(fallbackRole)': \(scenes.count) scenes, lineCounts: \(scenes.map { $0.lines.count })")
            for scene in scenes {
                let myLines = scene.lines.filter(\.isMine).count
                let otherLines = scene.lines.filter { !$0.isMine }.count
                print("  Scene \(scene.number) '\(scene.title)' (\(scene.heading)): total=\(scene.lines.count), mine=\(myLines), other=\(otherLines)")
            }
        }
        print("==========================================")
        return (doc, draft)
    }

    func testGreaseAuditionSidesPDFEndToEnd() async throws {
        let (doc, draft) = try await auditPDF(named: "Grease+Audition+Sides+V2")
        XCTAssertEqual(doc.pageCount, 32)
        XCTAssertEqual(draft.project, "Grease")
        XCTAssertGreaterThanOrEqual(draft.candidateRoles.count, 14)
        XCTAssertTrue(draft.hasSides)
        XCTAssertFalse(draft.availablePortions.isEmpty)

        let extractedChars = ScriptParser.extractCharacters(from: doc.fullText)
        XCTAssertTrue(extractedChars.contains("Sandy"))
        XCTAssertTrue(extractedChars.contains("Danny"))

        let sandyScenes = ScriptParser.parseScenes(from: doc.fullText, myRole: "Sandy")
        XCTAssertFalse(sandyScenes.isEmpty)
        for scene in sandyScenes {
            XCTAssertFalse(scene.heading.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber),
                           "Page number must never become a scene heading: \(scene.heading)")
        }
    }

    func testPilgrimageCastingSidesPDFEndToEnd() async throws {
        let (doc, draft) = try await auditPDF(named: "Pilgrimage_Casting_Sides")
        XCTAssertEqual(doc.pageCount, 6)
        XCTAssertEqual(draft.project, "Pilgrimage")
        XCTAssertEqual(draft.candidateRoles, ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"])
        XCTAssertNotEqual(draft.castingOffice, "Casting Sides")
        XCTAssertTrue(draft.hasSides)
        XCTAssertEqual(draft.availablePortions.count, 5)
        XCTAssertTrue(draft.asks.contains("Slate first"))
        XCTAssertTrue(draft.asks.contains("Landscape"))
        XCTAssertTrue(draft.asks.contains("Under 2 min"))
        XCTAssertEqual(draft.destination, .emailOrLink)
        XCTAssertEqual(draft.destinationDetail, "kalnaga.com/pilgrimage/casting.html")
        XCTAssertTrue(draft.includeSlate)

        let noorScenes = ScriptParser.parseScenes(from: doc.fullText, myRole: "Noor")
        XCTAssertFalse(noorScenes.isEmpty)
        XCTAssertTrue(noorScenes[0].lines.contains { $0.isMine && $0.text.count > 100 })

        let nadiaScenes = ScriptParser.parseScenes(from: doc.fullText, myRole: "Nadia")
        XCTAssertTrue(nadiaScenes.contains { $0.lines.contains(where: \.isMine) })
    }
}
