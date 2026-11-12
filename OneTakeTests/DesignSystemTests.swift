import XCTest
import SwiftUI
@testable import OneTake

final class DesignSystemTests: XCTestCase {
    func testControlSizes() {
        XCTAssertEqual(OTControlSize.large.height, 50)
        XCTAssertEqual(OTControlSize.medium.height, 40)
        XCTAssertEqual(OTControlSize.small.height, 34)
        XCTAssertEqual(OTControlSize.small.hitHeight, 44)
    }

    func testScales() {
        XCTAssertEqual([OTSpace.xxs, OTSpace.xs, OTSpace.s, OTSpace.m, OTSpace.l, OTSpace.xl, OTSpace.xxl], [2, 4, 8, 12, 16, 24, 32])
        XCTAssertEqual([OTRadius.xs, OTRadius.s, OTRadius.m, OTRadius.control, OTRadius.l, OTRadius.xl, OTRadius.card], [4, 8, 12, 14, 16, 20, 24])
        XCTAssertEqual(OTSpace.gutter, OT.gutter)
    }

    func testTypeTokensScaleWithDynamicType() {
        func h(_ size: DynamicTypeSize) -> CGFloat {
            UIHostingController(rootView: Text("Aa").font(.otBody).environment(\.dynamicTypeSize, size))
                .sizeThatFits(in: CGSize(width: 300, height: 500)).height
        }
        XCTAssertGreaterThan(h(.accessibility3), h(.large))
    }

    private func height(_ v: some View) -> CGFloat {
        UIHostingController(rootView: v.frame(width: 320)).sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testPrimaryAndSecondaryShareHeight() {
        XCTAssertEqual(height(Button("Continue") {}.buttonStyle(.ot(.primary))), 50)
        XCTAssertEqual(height(Button("Retake") {}.buttonStyle(.ot(.secondary))), 50)
    }

    func testMenuMatchesButtonHeight() {
        for size in [OTControlSize.large, .medium] {
            let b = height(Button("Camera") {}.buttonStyle(.ot(.secondary, size: size)))
            let m = height(OTMenuButton("Photos", systemImage: "photo", size: size) { Button("Front") {} })
            XCTAssertEqual(b, m, "\(size)")
        }
    }

    func testSmallButtonKeepsTapTarget() {
        XCTAssertEqual(height(Button("Edit") {}.buttonStyle(.ot(.secondary, size: .small, fullWidth: false))), 44)
    }

    func testButtonsGrowWithDynamicType() {
        let v = Button("Continue to slate") {}.buttonStyle(.ot(.primary))
            .environment(\.dynamicTypeSize, .accessibility3)
        XCTAssertGreaterThan(height(v), 50)
    }

    func testCameraSurfaceUsesLightForeground() {
        XCTAssertEqual(OTButtonStyle.foreground(for: .secondary, surface: .camera), OT.cameraLabel)
        XCTAssertEqual(OTButtonStyle.foreground(for: .secondary, surface: .standard), OT.labelPrimary)
    }
}
