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

    func testDocumentPageRouterSeparatesNoticeAndSidesPagesWithinBudget() throws {
        let greaseURL = try XCTUnwrap(resolvePDFURL(named: "Grease+Audition+Sides+V2"))
        let greasePDF = try XCTUnwrap(PDFDocument(url: greaseURL))
        let greasePages = (0..<greasePDF.pageCount).map {
            PDFGeometryExtractor.extractLines(from: greasePDF.page(at: $0)!, pageIndex: $0)
        }
        let greaseLayoutDoc = LayoutDocument(pages: greasePages)
        let greaseRouted = DocumentPageRouter.route(greaseLayoutDoc, tokenBudget: 900)

        XCTAssertTrue(greaseRouted.noticePages.contains(0))
        XCTAssertFalse(greaseRouted.sidesPages.isEmpty)
        XCTAssertEqual(Set(greaseRouted.noticePages).intersection(greaseRouted.sidesPages), [])
        XCTAssertFalse(greaseRouted.sidesLayoutLines.isEmpty)
        XCTAssertTrue(greaseRouted.sidesLayoutLines.allSatisfy { greaseRouted.sidesPages.contains($0.pageIndex) })
        XCTAssertLessThanOrEqual(greaseRouted.noticeTextSlice.split(whereSeparator: \.isWhitespace).count, 750)

        let pilgrimageURL = try XCTUnwrap(resolvePDFURL(named: "Pilgrimage_Casting_Sides"))
        let pilgrimagePDF = try XCTUnwrap(PDFDocument(url: pilgrimageURL))
        let pilgrimagePages = (0..<pilgrimagePDF.pageCount).map {
            PDFGeometryExtractor.extractLines(from: pilgrimagePDF.page(at: $0)!, pageIndex: $0)
        }
        let pilgrimageLayoutDoc = LayoutDocument(pages: pilgrimagePages)
        let pilgrimageRouted = DocumentPageRouter.route(pilgrimageLayoutDoc, tokenBudget: 900)

        XCTAssertTrue(pilgrimageRouted.noticePages.contains(0))
        XCTAssertFalse(pilgrimageRouted.sidesPages.isEmpty)
        XCTAssertLessThanOrEqual(pilgrimageRouted.noticeTextSlice.split(whereSeparator: \.isWhitespace).count, 750)
        XCTAssertEqual(pilgrimageRouted, DocumentPageRouter.route(pilgrimageLayoutDoc, tokenBudget: 900))
    }

    func testDocumentPageRouterHandlesMultiPageNoticeAndTailSubmissionPage() {
        let page0 = [
            LayoutLine(text: "CASTING NOTICE: HARBOR LIGHTS", rect: CGRect(x: 0.1, y: 0.9, width: 0.7, height: 0.03), pageIndex: 0),
            LayoutLine(text: "Production: Harbor Pictures | Director: Ava Chen", rect: CGRect(x: 0.1, y: 0.84, width: 0.7, height: 0.02), pageIndex: 0),
            LayoutLine(text: "SUBMISSION DEADLINE: November 28, 2026", rect: CGRect(x: 0.1, y: 0.78, width: 0.6, height: 0.02), pageIndex: 0)
        ]
        let page1 = [
            LayoutLine(text: "CHARACTER BREAKDOWN", rect: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.025), pageIndex: 1),
            LayoutLine(text: "ELENA (Lead, Female, 30-38) - Sharp investigative reporter.", rect: CGRect(x: 0.1, y: 0.84, width: 0.75, height: 0.02), pageIndex: 1),
            LayoutLine(text: "MARCUS (Supporting, Male, 40s) - Veteran dockworker.", rect: CGRect(x: 0.1, y: 0.78, width: 0.75, height: 0.02), pageIndex: 1)
        ]
        let page2 = [
            LayoutLine(text: "INT. PIER WAREHOUSE - NIGHT", rect: CGRect(x: 0.15, y: 0.9, width: 0.5, height: 0.02), pageIndex: 2),
            LayoutLine(text: "ELENA", rect: CGRect(x: 0.42, y: 0.82, width: 0.12, height: 0.02), pageIndex: 2),
            LayoutLine(text: "You knew the manifest was altered before the ship docked.", rect: CGRect(x: 0.25, y: 0.77, width: 0.55, height: 0.02), pageIndex: 2),
            LayoutLine(text: "MARCUS", rect: CGRect(x: 0.42, y: 0.70, width: 0.14, height: 0.02), pageIndex: 2),
            LayoutLine(text: "Keep your voice down. Half the crew is still inside.", rect: CGRect(x: 0.25, y: 0.65, width: 0.55, height: 0.02), pageIndex: 2),
            LayoutLine(text: "ELENA", rect: CGRect(x: 0.42, y: 0.58, width: 0.12, height: 0.02), pageIndex: 2),
            LayoutLine(text: "Then walk me out to the gate and tell me who paid you.", rect: CGRect(x: 0.25, y: 0.53, width: 0.55, height: 0.02), pageIndex: 2)
        ]
        let page3 = [
            LayoutLine(text: "EXT. HARBOR GATE - CONTINUOUS", rect: CGRect(x: 0.15, y: 0.9, width: 0.5, height: 0.02), pageIndex: 3),
            LayoutLine(text: "MARCUS", rect: CGRect(x: 0.42, y: 0.82, width: 0.14, height: 0.02), pageIndex: 3),
            LayoutLine(text: "It wasn't money, Elena. They had my brother's pension file.", rect: CGRect(x: 0.25, y: 0.77, width: 0.55, height: 0.02), pageIndex: 3),
            LayoutLine(text: "ELENA", rect: CGRect(x: 0.42, y: 0.70, width: 0.12, height: 0.02), pageIndex: 3),
            LayoutLine(text: "Give me the copy you kept and I can bury them tonight.", rect: CGRect(x: 0.25, y: 0.65, width: 0.55, height: 0.02), pageIndex: 3)
        ]
        let page4 = [
            LayoutLine(text: "SELF TAPE SUBMISSION & CALLBACK INSTRUCTIONS", rect: CGRect(x: 0.1, y: 0.9, width: 0.7, height: 0.025), pageIndex: 4),
            LayoutLine(text: "SLATE: Name, height, city, and agency in landscape framing.", rect: CGRect(x: 0.1, y: 0.84, width: 0.75, height: 0.02), pageIndex: 4),
            LayoutLine(text: "CALLBACK DATES: December 4, 2026 via Zoom.", rect: CGRect(x: 0.1, y: 0.78, width: 0.65, height: 0.02), pageIndex: 4),
            LayoutLine(text: "Email self-tape to casting@harborpictures.com", rect: CGRect(x: 0.1, y: 0.12, width: 0.65, height: 0.02), pageIndex: 4)
        ]

        let doc = LayoutDocument(pages: [page0, page1, page2, page3, page4])
        let routed = DocumentPageRouter.route(doc, tokenBudget: 900)

        XCTAssertEqual(routed.noticePages, [0, 1, 4])
        XCTAssertEqual(routed.sidesPages, [2, 3])
        XCTAssertTrue(routed.sidesLayoutLines.allSatisfy { $0.pageIndex == 2 || $0.pageIndex == 3 })
        XCTAssertTrue(routed.noticeTextSlice.contains("HARBOR LIGHTS"))
        XCTAssertTrue(routed.noticeTextSlice.contains("ELENA"))
        XCTAssertTrue(routed.noticeTextSlice.contains("casting@harborpictures.com"))
    }

    func testDocumentPageRouterEnforcesTokenBudgetOnLongNoticePages() {
        let filler = (0..<120).map { "Additional background detail number \($0) about wardrobe, parking, and holding area procedures." }
        let page0 = [
            "AUDITION NOTICE: NORTHERN STAR",
            "Role: CAPTAIN REYES (Lead, 40s)",
            "REQUIREMENTS: Slate first in horizontal landscape framing."
        ] + filler + [
            "SUBMISSION DEADLINE: Friday 5:00 PM",
            "Submit tapes to submit@northernstarcasting.org"
        ]
        let page1 = [
            "CALLBACK & PRODUCTION NOTES",
            "Callbacks scheduled for next Tuesday at Studio B."
        ] + filler + [
            "Contact portal: https://casting.northernstar.org/apply"
        ]

        let doc = LayoutDocument(
            pages: [
                PDFGeometryExtractor.syntheticLines(from: page0.joined(separator: "\n"), pageIndex: 0),
                PDFGeometryExtractor.syntheticLines(from: page1.joined(separator: "\n"), pageIndex: 1)
            ],
            reconstructedPages: [page0.joined(separator: "\n"), page1.joined(separator: "\n")]
        )
        let routed = DocumentPageRouter.route(doc, tokenBudget: 900)

        XCTAssertEqual(routed.noticePages, [0, 1])
        XCTAssertTrue(routed.sidesPages.isEmpty)
        let words = routed.noticeTextSlice.split(whereSeparator: \.isWhitespace).count
        XCTAssertLessThanOrEqual(words, 750)
        XCTAssertTrue(routed.noticeTextSlice.contains("NORTHERN STAR"))
        XCTAssertTrue(routed.noticeTextSlice.contains("REQUIREMENTS:"))
        XCTAssertTrue(routed.noticeTextSlice.contains("submit@northernstarcasting.org"))
        XCTAssertTrue(routed.noticeTextSlice.contains("https://casting.northernstar.org/apply"))
    }

    func testNoticeParserExtractsTailSubmissionPageViaDocumentPageRouter() {
        let pages = [
            """
            CASTING NOTICE: HARBOR LIGHTS
            Production: Harbor Pictures | Director: Ava Chen
            """,
            """
            INT. PIER WAREHOUSE - NIGHT

                        ELENA
            You knew the manifest was altered before the ship docked.

                        MARCUS
            Keep your voice down. Half the crew is still inside.
            """,
            """
            EXT. HARBOR GATE - CONTINUOUS

                        MARCUS
            It wasn't money, Elena. They had my brother's pension file.
            """,
            """
            SELF TAPE SUBMISSION & CALLBACK INSTRUCTIONS
            Please slate first in landscape framing.
            Email self-tape to casting@harborpictures.com
            """
        ]
        let draft = NoticeParser.parse(pages.joined(separator: "\n\n"), pages: pages)
        XCTAssertEqual(draft.project, "Harbor Lights")
        XCTAssertEqual(draft.destination, .email)
        XCTAssertEqual(draft.destinationDetail, "casting@harborpictures.com")
        XCTAssertTrue(draft.asks.contains("Slate first"))
        XCTAssertTrue(draft.asks.contains("Landscape"))
    }
}
