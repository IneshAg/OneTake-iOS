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

    @MainActor func testBottomBarIsOpaque() {
        let v = Color.red.frame(width: 320, height: 400)
            .otBottomBar { Button("Go") {}.buttonStyle(.otPrimary) }
        let img = ImageRenderer(content: v).uiImage!
        let px = img.rgba(at: CGPoint(x: 4, y: img.size.height - 2))
        XCTAssertEqual(px.a, 1, accuracy: 0.01)
        XCTAssertFalse(px.r > 0.9 && px.g < 0.1 && px.b < 0.1, "content bleeds through the bar")
    }

    func testNavHeaderHeight() { XCTAssertEqual(height(OTNavHeader(title: "Audition Headshots")), 44) }
    func testIconButtonIsMinimumTapTarget() {
        let size = UIHostingController(rootView: OTIconButton("xmark", accessibilityLabel: "Close") {})
            .sizeThatFits(in: CGSize(width: 200, height: 200))
        XCTAssertEqual(size, CGSize(width: 44, height: 44))
    }
    func testChipKeepsTapTarget() { XCTAssertGreaterThanOrEqual(height(OTChip("Front") {}), 44) }
    func testScreenStartsWithHeader() {
        // header (44) + content (100) + stack spacing (16) + bottom padding (24), non-scrolling
        XCTAssertEqual(height(OTScreen(title: "T", scrolls: false) { Color.clear.frame(height: 100) }), 184)
    }

    func testHeadshotAngleTitles() {
        XCTAssertEqual(HeadshotAngle.allCases.map(\.title), ["Front", "Left profile", "Right profile"])
    }
}

extension UIImage {
    func rgba(at point: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        guard let cgImage = cgImage else { return (0, 0, 0, 0) }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return (0, 0, 0, 0) }
        context.draw(cgImage, in: CGRect(x: -point.x, y: -(CGFloat(cgImage.height) - point.y - 1), width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (
            CGFloat(pixel[0]) / 255.0,
            CGFloat(pixel[1]) / 255.0,
            CGFloat(pixel[2]) / 255.0,
            CGFloat(pixel[3]) / 255.0
        )
    }
}
