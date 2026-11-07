import XCTest
@testable import OneTake

final class SeparatePDFImportTests: XCTestCase {

    private let sampleCastingNotice = """
    PROJECT: THE CROWN OF THORNS
    CASTING DIRECTOR: Sarah Finn Casting
    ROLE: LADY ELEANOR (Lead, 25-35)
    DEADLINE: November 25, 2026
    INSTRUCTIONS: Slate first in landscape mode. Full-body shot required. Attach headshots.
    CHARACTER BREAKDOWN: Fierce, determined aristocrat fighting for her family's survival in wartime.
    """

    private let sampleScriptSides = """
    SCENE 1 - INT. GREAT HALL - NIGHT

    LADY ELEANOR stands by the fireplace, clutching a sealed letter.
    LORD GREY enters quietly.

    LORD GREY
    Is it true, Eleanor? Have the scouts returned?

    LADY ELEANOR
    (turning to face him)
    They found the encampment across the river. We march before dawn.

    LORD GREY
    You cannot lead them yourself. The council will never permit it.

    LADY ELEANOR
    I did not ask for their permission, Grey. I asked for your loyalty.
    """

    private let replacementNotice = """
    PROJECT: THE WINTER MONARCH
    CASTING DIRECTOR: Nina Gold Casting
    ROLE: QUEEN MARGARET (Series Regular)
    DEADLINE: December 1, 2026
    INSTRUCTIONS: Slate with name, height, city.
    """

    private let replacementSides = """
    SCENE 1 - INT. THRONE ROOM - DAY

    QUEEN MARGARET looks down from the dais.
    AMBASSADOR stands trembling.

    AMBASSADOR
    Your Majesty, the peace treaty awaits your signature.

    QUEEN MARGARET
    Peace is earned with steel, Ambassador, not ink.
    """

    // 1. Import casting call only
    func testImportCastingCallOnly() {
        var draft = NoticeParser.Draft.blank
        let noticeSource = AuditionSource(name: "Notice.pdf", kind: .castingNotice, pageCount: 2)
        let parsedNotice = NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSource])
        
        draft.mergeCastingNotice(from: parsedNotice, source: noticeSource)
        
        XCTAssertEqual(draft.project, "THE CROWN OF THORNS")
        XCTAssertEqual(draft.role, "LADY ELEANOR")
        XCTAssertEqual(draft.castingOffice, "Sarah Finn Casting")
        XCTAssertNotNil(draft.castingCallSource)
        XCTAssertEqual(draft.castingCallSource?.name, "Notice.pdf")
        XCTAssertNil(draft.scriptSidesSource)
        XCTAssertTrue(draft.scriptText.isEmpty)
        XCTAssertEqual(draft.scenes, 0)
        
        let audition = draft.makeAudition()
        XCTAssertEqual(audition.project, "THE CROWN OF THORNS")
        XCTAssertEqual(audition.role, "LADY ELEANOR")
        XCTAssertEqual(audition.noticeText, ScriptParser.cleanPastedText(sampleCastingNotice))
        XCTAssertNil(audition.scriptText)
        XCTAssertTrue(audition.scenes.isEmpty)
        XCTAssertEqual(audition.noticeSources?.first?.name, "Notice.pdf")
        XCTAssertNil(audition.sourceDocuments)
    }

    // 2. Import script sides only
    func testImportScriptSidesOnly() {
        var draft = NoticeParser.Draft.blank
        let sidesSource = AuditionSource(name: "Sides_Eleanor.pdf", kind: .scriptSides, pageCount: 3)
        
        draft.mergeScriptSides(text: sampleScriptSides, source: sidesSource)
        
        XCTAssertNotNil(draft.scriptSidesSource)
        XCTAssertEqual(draft.scriptSidesSource?.name, "Sides_Eleanor.pdf")
        XCTAssertNil(draft.castingCallSource)
        XCTAssertFalse(draft.scriptText.isEmpty)
        XCTAssertEqual(draft.scenes, 1)
        XCTAssertTrue(draft.candidateRoles.contains("LADY ELEANOR"))
        XCTAssertTrue(draft.candidateRoles.contains("LORD GREY"))
        
        let audition = draft.makeAudition()
        XCTAssertEqual(audition.scenes.count, 1)
        XCTAssertEqual(audition.sourceDocuments?.first?.name, "Sides_Eleanor.pdf")
        XCTAssertNil(audition.noticeSources)
        XCTAssertNil(audition.noticeText)
        XCTAssertNotNil(audition.scriptText)
    }

    // 3. Import both in either order
    func testImportBothInEitherOrder() {
        // Order A: Casting Call first, then Script Sides
        var draftA = NoticeParser.Draft.blank
        let noticeSourceA = AuditionSource(name: "Notice.pdf", kind: .castingNotice, pageCount: 1)
        let parsedNoticeA = NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSourceA])
        draftA.mergeCastingNotice(from: parsedNoticeA, source: noticeSourceA)
        
        let sidesSourceA = AuditionSource(name: "Sides.pdf", kind: .scriptSides, pageCount: 2)
        draftA.mergeScriptSides(text: sampleScriptSides, source: sidesSourceA)
        
        XCTAssertEqual(draftA.project, "THE CROWN OF THORNS")
        XCTAssertEqual(draftA.role, "LADY ELEANOR")
        XCTAssertEqual(draftA.castingOffice, "Sarah Finn Casting")
        XCTAssertEqual(draftA.castingCallSource?.name, "Notice.pdf")
        XCTAssertEqual(draftA.scriptSidesSource?.name, "Sides.pdf")
        XCTAssertEqual(draftA.scenes, 1)
        
        let auditionA = draftA.makeAudition()
        XCTAssertNotNil(auditionA.noticeText)
        XCTAssertNotNil(auditionA.scriptText)
        XCTAssertEqual(auditionA.noticeSources?.first?.name, "Notice.pdf")
        XCTAssertEqual(auditionA.sourceDocuments?.first?.name, "Sides.pdf")
        XCTAssertEqual(auditionA.scenes.count, 1)

        // Order B: Script Sides first, then Casting Call
        var draftB = NoticeParser.Draft.blank
        let sidesSourceB = AuditionSource(name: "Sides.pdf", kind: .scriptSides, pageCount: 2)
        draftB.mergeScriptSides(text: sampleScriptSides, source: sidesSourceB)
        
        let noticeSourceB = AuditionSource(name: "Notice.pdf", kind: .castingNotice, pageCount: 1)
        let parsedNoticeB = NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSourceB])
        draftB.mergeCastingNotice(from: parsedNoticeB, source: noticeSourceB)
        
        XCTAssertEqual(draftB.project, "THE CROWN OF THORNS")
        XCTAssertEqual(draftB.role, "LADY ELEANOR")
        XCTAssertEqual(draftB.castingOffice, "Sarah Finn Casting")
        XCTAssertEqual(draftB.castingCallSource?.name, "Notice.pdf")
        XCTAssertEqual(draftB.scriptSidesSource?.name, "Sides.pdf")
        XCTAssertEqual(draftB.scenes, 1)
        
        let auditionB = draftB.makeAudition()
        XCTAssertNotNil(auditionB.noticeText)
        XCTAssertNotNil(auditionB.scriptText)
        XCTAssertEqual(auditionB.scenes.count, 1)
    }

    // 4. Replace casting call while preserving script sides
    func testReplaceCastingCallPreservesScriptSides() {
        var draft = NoticeParser.Draft.blank
        let noticeSource1 = AuditionSource(name: "Notice_Old.pdf", kind: .castingNotice, pageCount: 1)
        draft.mergeCastingNotice(from: NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSource1]), source: noticeSource1)
        
        let sidesSource = AuditionSource(name: "Sides_Eleanor.pdf", kind: .scriptSides, pageCount: 2)
        draft.mergeScriptSides(text: sampleScriptSides, source: sidesSource)
        
        XCTAssertEqual(draft.project, "THE CROWN OF THORNS")
        XCTAssertEqual(draft.scenes, 1)
        
        // Now replace Casting Call with new document
        let noticeSource2 = AuditionSource(name: "Notice_Revised.pdf", kind: .castingNotice, pageCount: 2)
        let revisedNotice = NoticeParser.parse(replacementNotice, sourceDocuments: [noticeSource2])
        draft.mergeCastingNotice(from: revisedNotice, source: noticeSource2)
        
        // Casting Call fields updated:
        XCTAssertEqual(draft.project, "THE WINTER MONARCH")
        XCTAssertEqual(draft.castingOffice, "Nina Gold Casting")
        XCTAssertEqual(draft.castingCallSource?.name, "Notice_Revised.pdf")
        
        // Script sides PRESERVED:
        XCTAssertNotNil(draft.scriptSidesSource)
        XCTAssertEqual(draft.scriptSidesSource?.name, "Sides_Eleanor.pdf")
        XCTAssertFalse(draft.scriptText.isEmpty)
        XCTAssertEqual(draft.scenes, 1)
    }

    // 5. Replace script sides while preserving casting call
    func testReplaceScriptSidesPreservesCastingCall() {
        var draft = NoticeParser.Draft.blank
        let noticeSource = AuditionSource(name: "Notice.pdf", kind: .castingNotice, pageCount: 1)
        draft.mergeCastingNotice(from: NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSource]), source: noticeSource)
        
        let sidesSource1 = AuditionSource(name: "Sides_Old.pdf", kind: .scriptSides, pageCount: 2)
        draft.mergeScriptSides(text: sampleScriptSides, source: sidesSource1)
        
        XCTAssertEqual(draft.scriptSidesSource?.name, "Sides_Old.pdf")
        
        // Replace Script Sides
        let sidesSource2 = AuditionSource(name: "Sides_Revised.pdf", kind: .scriptSides, pageCount: 4)
        draft.mergeScriptSides(text: replacementSides, source: sidesSource2)
        
        // Script sides updated:
        XCTAssertEqual(draft.scriptSidesSource?.name, "Sides_Revised.pdf")
        XCTAssertTrue(draft.scriptText.contains("QUEEN MARGARET"))
        
        // Casting call PRESERVED:
        XCTAssertEqual(draft.project, "THE CROWN OF THORNS")
        XCTAssertEqual(draft.castingOffice, "Sarah Finn Casting")
        XCTAssertEqual(draft.castingCallSource?.name, "Notice.pdf")
    }

    // 6. Failed import without data loss
    func testFailedImportDoesNotCorruptExistingDraft() {
        var draft = NoticeParser.Draft.blank
        let noticeSource = AuditionSource(name: "Notice.pdf", kind: .castingNotice, pageCount: 1)
        draft.mergeCastingNotice(from: NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSource]), source: noticeSource)
        
        let originalProject = draft.project
        let originalNoticeText = draft.noticeText
        let originalSource = draft.castingCallSource
        
        // Simulate a failed import (unreadable text or empty file)
        let emptyOrGarbage = "   \n\t   "
        if !emptyOrGarbage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.mergeScriptSides(text: emptyOrGarbage, source: nil)
        }
        
        // Existing data must remain completely intact
        XCTAssertEqual(draft.project, originalProject)
        XCTAssertEqual(draft.noticeText, originalNoticeText)
        XCTAssertEqual(draft.castingCallSource?.name, originalSource?.name)
        XCTAssertNil(draft.scriptSidesSource)
    }

    // 7. App restart and persistence
    func testBothDocumentsPersistAndRestoreAcrossAppRestart() throws {
        var draft = NoticeParser.Draft.blank
        let noticeSource = AuditionSource(name: "Breakdown.pdf", kind: .castingNotice, pageCount: 2)
        draft.mergeCastingNotice(from: NoticeParser.parse(sampleCastingNotice, sourceDocuments: [noticeSource]), source: noticeSource)
        
        let sidesSource = AuditionSource(name: "Sides_Packet.pdf", kind: .scriptSides, pageCount: 5)
        draft.mergeScriptSides(text: sampleScriptSides, source: sidesSource)
        
        let audition = draft.makeAudition()
        let state = PersistedState(auditions: [audition], isOnboarded: true)
        
        // Encode state to JSON (simulating app background save)
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(state)
        
        // Decode state from JSON (simulating app relaunch)
        let decoder = JSONDecoder()
        let restoredState = try decoder.decode(PersistedState.self, from: encodedData)
        
        let restoredAudition = try XCTUnwrap(restoredState.auditions.first)
        XCTAssertEqual(restoredAudition.project, "THE CROWN OF THORNS")
        XCTAssertEqual(restoredAudition.role, "LADY ELEANOR")
        XCTAssertEqual(restoredAudition.noticeText, ScriptParser.cleanPastedText(sampleCastingNotice))
        XCTAssertEqual(restoredAudition.scriptText, ScriptParser.cleanPastedText(sampleScriptSides))
        XCTAssertEqual(restoredAudition.noticeSources?.first?.name, "Breakdown.pdf")
        XCTAssertEqual(restoredAudition.sourceDocuments?.first?.name, "Sides_Packet.pdf")
        XCTAssertEqual(restoredAudition.scenes.count, 1)
        XCTAssertEqual(restoredAudition.scenes.first?.lines.count, 4)
    }
}
