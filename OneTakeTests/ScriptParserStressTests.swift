import XCTest
import UIKit
@testable import OneTake

final class ScriptParserStressTests: XCTestCase {

    /// Verifies end-to-end OCR and parser pipeline on the user's actual uploaded flyer image (test.png).
    func testActualUploadedFlyerImageOCRAndParserStress() async throws {
        // Resolve path to test.png located in the project root
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OneTakeTests
            .deletingLastPathComponent() // Project root
        let imageURL = rootURL.appendingPathComponent("test.png")

        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw XCTSkip("test.png not found at \(imageURL.path)")
        }

        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            XCTFail("Failed to decode UIImage from \(imageURL.path)")
            return
        }

        // 1. Run through production OCR pipeline
        let pages = await NoticeOCR.recognizePages(in: [image])
        XCTAssertFalse(pages.isEmpty, "OCR must extract text from test.png")
        let ocrText = pages.joined(separator: "\n")

        print("--- EXTRACTED OCR TEXT FROM test.png ---")
        print(ocrText)
        print("----------------------------------------")

        // 2. Verify NoticeOCR readable check passes
        XCTAssertTrue(NoticeOCR.looksReadable(ocrText), "OCR text must pass readability checks")

        // 3. Verify NoticeParser flags it as notice-only (flyer / casting call)
        let isNotice = NoticeParser.isNoticeOnly(ocrText)
        XCTAssertTrue(isNotice, "Mukesh Chhabra Casting flyer must be identified as notice-only")

        // 4. Verify ScriptParser does NOT generate bogus scenes or dialogue from flyer requirements
        let scenes = ScriptParser.parseScenes(from: ocrText, myRole: "MALE")
        XCTAssertTrue(scenes.isEmpty, "Flyer must not yield false script scenes: found \(scenes.count) scenes")

        // 5. Verify ScriptParser character extraction does not pick up 'GENDER' or 'REQUIREMENT'
        let characters = ScriptParser.extractCharacters(from: ocrText)
        XCTAssertFalse(characters.contains("GENDER"), "GENDER must not be extracted as a character")
        XCTAssertFalse(characters.contains("REQUIREMENT"), "REQUIREMENT must not be extracted as a character")
        XCTAssertFalse(characters.contains("TURBAN"), "TURBAN must not be extracted as a character")
        XCTAssertFalse(characters.contains("CONTACT"), "CONTACT must not be extracted as a character")

        // 6. Verify deterministic notice parser extracts key fields cleanly
        let draft = NoticeParser.parse(ocrText, pages: pages)
        XCTAssertFalse(draft.candidateRoles.isEmpty, "Should identify candidate roles from casting call")
    }

    /// Stress tests the Core ML script element classifier and parser against a 25-page script (1,500+ lines).
    func testTwentyFivePageScriptParsingPerformanceAndAccuracy() {
        let pageCount = 25
        let linesPerPage = 60
        var scriptLines: [String] = []

        let characters = ["HAMLET", "OPHELIA", "CLAUDIUS", "GERTRUDE", "HORATIO", "POLONIUS"]
        let dialogues = [
            "To be, or not to be, that is the question:",
            "Whether 'tis nobler in the mind to suffer",
            "The slings and arrows of outrageous fortune,",
            "Or to take arms against a sea of troubles",
            "And by opposing end them.",
            "My lord, I have remembrances of yours,",
            "That I have longed long to re-deliver;",
            "I pray you, now receive them.",
            "No, not I; I never gave you aught.",
            "My honour'd lord, you know right well you did;"
        ]

        for page in 1...pageCount {
            scriptLines.append("SCENE \(page) - INT. CASTLE ELSINORE - DAY")
            scriptLines.append("")
            for lineIndex in 0..<linesPerPage {
                let speaker = characters[(page + lineIndex) % characters.count]
                let dialogue = dialogues[(page * 3 + lineIndex) % dialogues.count]
                scriptLines.append(speaker)
                if lineIndex % 7 == 0 {
                    scriptLines.append("(thoughtfully)")
                }
                scriptLines.append(dialogue)
                scriptLines.append("")
            }
        }

        let fullScript = scriptLines.joined(separator: "\n")
        let totalLines = scriptLines.count
        XCTAssertGreaterThanOrEqual(totalLines, 1500, "Script should have at least 1500 lines for 25 pages")

        // Measure parsing execution time
        let start = DispatchTime.now()
        let scenes = ScriptParser.parseScenes(from: fullScript, myRole: "HAMLET")
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        print("Parsed \(scenes.count) scenes (\(totalLines) lines) across \(pageCount) pages in \(String(format: "%.3f", elapsed))s")

        // Assert performance: 25 pages should parse in well under 1.5 seconds on-device
        XCTAssertLessThan(elapsed, 1.5, "Parsing 25 pages should complete in under 1.5 seconds")
        XCTAssertEqual(scenes.count, pageCount, "Must correctly identify all \(pageCount) scene headings")

        // Assert accuracy of role matching and dialogue attribution
        var myLinesCount = 0
        var otherLinesCount = 0
        for scene in scenes {
            for line in scene.lines {
                if line.isMine {
                    XCTAssertEqual(line.character, "Hamlet")
                    myLinesCount += 1
                } else {
                    XCTAssertNotEqual(line.character, "Hamlet")
                    otherLinesCount += 1
                }
            }
        }

        XCTAssertGreaterThan(myLinesCount, 0, "Must extract Hamlet's lines")
        XCTAssertGreaterThan(otherLinesCount, 0, "Must extract other characters' lines")

        // Test hierarchical scene portion chunking on 25 pages
        let portions = ScriptParser.identifyScenePortions(from: fullScript)
        XCTAssertEqual(portions.count, pageCount, "Portions must match total scenes")
        for portion in portions {
            XCTAssertTrue(portion.characters.contains("HAMLET"))
        }
    }

    /// Stress tests a massive 50-page script (3,000+ lines) to ensure zero memory crashes and fast completion.
    func testFiftyPageScriptMassiveStress() {
        let pageCount = 50
        var scriptLines: [String] = []

        for p in 1...pageCount {
            scriptLines.append("INT. LOCATION \(p) - NIGHT")
            scriptLines.append("A dim room with shadow across the floor.")
            scriptLines.append("")
            scriptLines.append("DETECTIVE")
            scriptLines.append("Where were you at midnight?")
            scriptLines.append("")
            scriptLines.append("SUSPECT")
            scriptLines.append("(hesitating)")
            scriptLines.append("I was asleep at home.")
            scriptLines.append("")
            scriptLines.append("DETECTIVE")
            scriptLines.append("Your car was seen by the docks.")
            scriptLines.append("")
            scriptLines.append("SUSPECT")
            scriptLines.append("Someone stole it, I swear!")
            scriptLines.append("")
        }

        let fullScript = scriptLines.joined(separator: "\n")
        let start = DispatchTime.now()
        let scenes = ScriptParser.parseScenes(from: fullScript, myRole: "DETECTIVE")
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        print("Parsed 50-page massive script in \(String(format: "%.3f", elapsed))s")
        XCTAssertLessThan(elapsed, 2.5, "Parsing 50 pages must take less than 2.5 seconds")
        XCTAssertEqual(scenes.count, 50)
    }

    /// Tests adversarial notice formatting: bullet points, Unicode symbols, emails, and phone numbers.
    func testAdversarialNoticeAndFlyerFormatting() {
        let adversarialNotice = """
        *** URGENT AUDITION NOTICE ***
        PRODUCTION: INDEPENDENT FEATURE FILM
        SHOOT DATES: DEC 1 - DEC 15, 2026
        LOCATION: VANCOUVER, BC
        
        • ROLE: SARAH (LEAD) - FEMALE, 25-35
        Confident, sharp, quick-witted detective.
        
        • ROLE: MARCUS (SUPPORTING) - MALE, 30-40
        Quiet, observant forensic analyst.
        
        SUBMISSION REQUIREMENTS:
        - Self-tape reading sides below
        - Resume & headshot (PDF only)
        - Contact: casting@productionco.com / +1 (555) 234-5678
        - Deadline: Friday 5:00 PM EST
        """

        let scenes = ScriptParser.parseScenes(from: adversarialNotice, myRole: "SARAH")
        XCTAssertTrue(scenes.isEmpty, "Audition metadata and role specs must not parse into script scenes")

        let isNotice = NoticeParser.isNoticeOnly(adversarialNotice)
        XCTAssertTrue(isNotice, "Adversarial notice must be recognized as notice-only")
    }
}
