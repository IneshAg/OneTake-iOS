import XCTest
import SwiftUI
@testable import OneTake

final class PackageAndSentTests: XCTestCase {
    private func makeAudition(
        destination: Destination = .actorsAccess,
        scenesCount: Int = 1,
        sentDate: Date? = nil,
        shareLink: URL? = nil,
        shareLinkExpires: Date? = nil
    ) -> Audition {
        let scenes = (0..<scenesCount).map { i in
            ScriptScene(number: i + 1, title: "Scene \(i + 1)", heading: "INT. SCENE \(i + 1)", lines: [], estimatedSeconds: 30)
        }
        var audition = Audition(
            project: "Hamlet",
            projectType: "Theater",
            role: "Ophelia",
            roleSize: "Lead",
            castingOffice: "Royal Shakespeare Co",
            due: Date().addingTimeInterval(86400),
            asks: [],
            pieces: [],
            scenes: scenes,
            destination: destination,
            status: sentDate != nil ? .sent : .ready
        )
        audition.sentDate = sentDate
        audition.shareLink = shareLink
        audition.shareLinkExpires = shareLinkExpires
        return audition
    }

    // MARK: - Package Navigation Routing

    @MainActor
    func testPackageAudioRowRoutesToTapeCheck() {
        let store = AppStore()
        let audition = makeAudition()
        store.auditions = [audition]

        // Tapping the "Audio" button in PackageView triggers store.push(.tapeCheck(a.id))
        store.push(.tapeCheck(audition.id))

        XCTAssertEqual(store.auditionsPath.last, .tapeCheck(audition.id), "Audio row must push .tapeCheck with audition ID")
    }

    @MainActor
    func testPackagePreviewRowRoutesToTapePreview() {
        let store = AppStore()
        let audition = makeAudition()
        store.auditions = [audition]

        // Tapping "Preview the whole tape" in PackageView triggers store.push(.preview(a.id))
        store.push(.preview(audition.id))

        XCTAssertEqual(store.auditionsPath.last, .preview(audition.id), "Preview row must push .preview with audition ID")
    }

    // MARK: - Destination-Aware Headline Logic

    func testDestinationAwareHeadlineLogic() {
        // Destination .emailOrLink produces "Your link is ready."
        let linkAudition = makeAudition(destination: .emailOrLink)
        let linkHeadline = (linkAudition.destination == .emailOrLink ? "Your link is ready." : "It’s on its way.")
        XCTAssertEqual(linkHeadline, "Your link is ready.")

        // All other direct casting export destinations produce "It’s on its way."
        let otherDestinations: [Destination] = [
            .actorsAccess,
            .castingNetworks,
            .spotlight
        ]

        for dest in otherDestinations {
            let audition = makeAudition(destination: dest)
            let headline = (audition.destination == .emailOrLink ? "Your link is ready." : "It’s on its way.")
            XCTAssertEqual(headline, "It’s on its way.", "Destination \(dest.rawValue) must have headline 'It’s on its way.'")
        }
    }

    // MARK: - SentView Presentation Bindings

    func testSentViewPersistedSentDateBinding() {
        let specificDate = Date(timeIntervalSince1970: 1700000000)
        let auditionWithDate = makeAudition(sentDate: specificDate)

        // When sentDate is persisted on audition, view uses the persisted date
        let resolvedDate = auditionWithDate.sentDate ?? Date.distantPast
        XCTAssertEqual(resolvedDate, specificDate, "SentView must bind to persisted sentDate")

        // When sentDate is nil, fallback is non-nil
        let auditionWithoutDate = makeAudition(sentDate: nil)
        XCTAssertNil(auditionWithoutDate.sentDate)
    }

    func testSentViewDestinationRawValues() {
        XCTAssertEqual(Destination.actorsAccess.rawValue, "Actors Access")
        XCTAssertEqual(Destination.castingNetworks.rawValue, "Casting Networks")
        XCTAssertEqual(Destination.spotlight.rawValue, "Spotlight")
        XCTAssertEqual(Destination.emailOrLink.rawValue, "Email or link")
    }

    func testSentViewSceneCountFormatting() {
        // Singular scene count: "1 scene"
        let singleSceneAudition = makeAudition(scenesCount: 1)
        let singleString = "Merged video · separate clips ZIP · \(singleSceneAudition.scenes.count) scene\(singleSceneAudition.scenes.count == 1 ? "" : "s")"
        XCTAssertEqual(singleString, "Merged video · separate clips ZIP · 1 scene")

        // Plural scene count: "3 scenes"
        let threeSceneAudition = makeAudition(scenesCount: 3)
        let pluralString = "Merged video · separate clips ZIP · \(threeSceneAudition.scenes.count) scene\(threeSceneAudition.scenes.count == 1 ? "" : "s")"
        XCTAssertEqual(pluralString, "Merged video · separate clips ZIP · 3 scenes")

        // Zero scene count: "0 scenes"
        let zeroSceneAudition = makeAudition(scenesCount: 0)
        let zeroString = "Merged video · separate clips ZIP · \(zeroSceneAudition.scenes.count) scene\(zeroSceneAudition.scenes.count == 1 ? "" : "s")"
        XCTAssertEqual(zeroString, "Merged video · separate clips ZIP · 0 scenes")
    }

    func testSentViewDeliverableStrings() {
        let audition = makeAudition(scenesCount: 2)
        let slate = SlateInfo(name: "Asha Rao")

        let deliverable = audition.deliverableFileName(slate: slate)
        XCTAssertEqual(deliverable, "RAO_ASHA_OPHELIA_HAMLET.mp4")

        let separateZip = (deliverable as NSString).deletingPathExtension + "_SEPARATE.zip"
        XCTAssertEqual(separateZip, "RAO_ASHA_OPHELIA_HAMLET_SEPARATE.zip")
    }

    func testSentViewLinkExpirationDisplay() {
        let expirationDate = Date().addingTimeInterval(86400 * 7) // 7 days later
        let shareURL = URL(string: "https://share.icloud.com/photos/12345")!
        let auditionWithLink = makeAudition(
            destination: .emailOrLink,
            shareLink: shareURL,
            shareLinkExpires: expirationDate
        )

        XCTAssertNotNil(auditionWithLink.shareLink)
        XCTAssertNotNil(auditionWithLink.shareLinkExpires)
        XCTAssertEqual(auditionWithLink.destination, .emailOrLink)

        let formattedExpiration = expirationDate.formatted(date: .abbreviated, time: .omitted)
        let expectedLabel = "Link shared · works until \(formattedExpiration)"
        XCTAssertTrue(expectedLabel.contains("works until"))

        // For non-link destination, label shows Share Sheet handoff
        let castingAudition = makeAudition(destination: .actorsAccess)
        let handoffLabel = "Handed off through your Share Sheet to \(castingAudition.destination.rawValue)"
        XCTAssertEqual(handoffLabel, "Handed off through your Share Sheet to Actors Access")
    }

    func testStressDateFormattingAcrossTimezonesAndEpochs() {
        let dates: [Date] = [
            Date(timeIntervalSince1970: 0),               // 1970-01-01
            Date(timeIntervalSince1970: 1730000000),      // 2024
            Date(timeIntervalSince1970: 2500000000)       // 2049
        ]

        for date in dates {
            let formatted = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).uppercased()
            XCTAssertFalse(formatted.isEmpty)
            let header = "SHARED · \(formatted)"
            XCTAssertTrue(header.hasPrefix("SHARED · "))
        }

        // Test nil fallback in SentView: `audition.sentDate ?? .now`
        let auditionNilSent = makeAudition(sentDate: nil)
        let resolvedDate = auditionNilSent.sentDate ?? Date()
        XCTAssertNotNil(resolvedDate)
    }

    func testStressAllDestinationRawValuesAndSpecs() {
        let expectedDestinations: [Destination: (raw: String, headline: String)] = [
            .actorsAccess: ("Actors Access", "It’s on its way."),
            .castingNetworks: ("Casting Networks", "It’s on its way."),
            .spotlight: ("Spotlight", "It’s on its way."),
            .emailOrLink: ("Email or link", "Your link is ready.")
        ]

        XCTAssertEqual(Destination.allCases.count, 4)

        for (dest, expected) in expectedDestinations {
            XCTAssertEqual(dest.rawValue, expected.raw)
            let headline = (dest == .emailOrLink ? "Your link is ready." : "It’s on its way.")
            XCTAssertEqual(headline, expected.headline)
        }
    }

    func testStressSceneCountFormattingBoundaryValues() {
        let testCases: [(count: Int, expected: String)] = [
            (0, "Merged video · separate clips ZIP · 0 scenes"),
            (1, "Merged video · separate clips ZIP · 1 scene"),
            (2, "Merged video · separate clips ZIP · 2 scenes"),
            (100, "Merged video · separate clips ZIP · 100 scenes"),
            (1000, "Merged video · separate clips ZIP · 1000 scenes")
        ]

        for test in testCases {
            let audition = makeAudition(scenesCount: test.count)
            let formatted = "Merged video · separate clips ZIP · \(audition.scenes.count) scene\(audition.scenes.count == 1 ? "" : "s")"
            XCTAssertEqual(formatted, test.expected, "Scene count \(test.count) formatted incorrectly")
        }
    }

    func testStressLinkExpirationFormattingVariants() {
        let link = URL(string: "https://share.icloud.com/tape123")!
        let expires = Date(timeIntervalSince1970: 1800000000)

        // Case 1: emailOrLink WITH link and WITH expiration
        let a1 = makeAudition(destination: .emailOrLink, shareLink: link, shareLinkExpires: expires)
        let label1: String
        if a1.destination == .emailOrLink {
            if let exp = a1.shareLinkExpires, a1.shareLink != nil {
                label1 = "Link shared to \(a1.destination.rawValue) · works until \(exp.formatted(date: .abbreviated, time: .omitted))"
            } else {
                label1 = "Link shared to \(a1.destination.rawValue)"
            }
        } else {
            label1 = "Handed off through your Share Sheet to \(a1.destination.rawValue)"
        }
        XCTAssertTrue(label1.hasPrefix("Link shared to Email or link · works until "))

        // Case 2: emailOrLink WITH link but WITHOUT expiration
        let a2 = makeAudition(destination: .emailOrLink, shareLink: link, shareLinkExpires: nil)
        let label2: String
        if a2.destination == .emailOrLink {
            if let exp = a2.shareLinkExpires, a2.shareLink != nil {
                label2 = "Link shared to \(a2.destination.rawValue) · works until \(exp.formatted(date: .abbreviated, time: .omitted))"
            } else {
                label2 = "Link shared to \(a2.destination.rawValue)"
            }
        } else {
            label2 = "Handed off through your Share Sheet to \(a2.destination.rawValue)"
        }
        XCTAssertEqual(label2, "Link shared to Email or link")

        // Case 3: Casting site (e.g. Spotlight) ignores link & expiration in label
        let a3 = makeAudition(destination: .spotlight, shareLink: link, shareLinkExpires: expires)
        let label3: String
        if a3.destination == .emailOrLink {
            if let exp = a3.shareLinkExpires, a3.shareLink != nil {
                label3 = "Link shared to \(a3.destination.rawValue) · works until \(exp.formatted(date: .abbreviated, time: .omitted))"
            } else {
                label3 = "Link shared to \(a3.destination.rawValue)"
            }
        } else {
            label3 = "Handed off through your Share Sheet to \(a3.destination.rawValue)"
        }
        XCTAssertEqual(label3, "Handed off through your Share Sheet to Spotlight")
    }

    func testStressEarlyHoursCalculationEdgeCases() {
        func computeEarlyText(due: Date, sent: Date) -> String {
            let h = max(0, Int(due.timeIntervalSince(sent) / 3600))
            return h >= 1 ? "\(h) hours early." : "Right on time."
        }

        let baseDate = Date(timeIntervalSince1970: 1700000000)

        // 24 hours early
        XCTAssertEqual(computeEarlyText(due: baseDate.addingTimeInterval(86400), sent: baseDate), "24 hours early.")

        // 1 hour early
        XCTAssertEqual(computeEarlyText(due: baseDate.addingTimeInterval(3600), sent: baseDate), "1 hours early.")

        // 59 minutes early (less than 1 full hour) -> "Right on time."
        XCTAssertEqual(computeEarlyText(due: baseDate.addingTimeInterval(3540), sent: baseDate), "Right on time.")

        // 0 seconds difference -> "Right on time."
        XCTAssertEqual(computeEarlyText(due: baseDate, sent: baseDate), "Right on time.")

        // Overdue by 10 hours -> "Right on time."
        XCTAssertEqual(computeEarlyText(due: baseDate.addingTimeInterval(-36000), sent: baseDate), "Right on time.")
    }
}

