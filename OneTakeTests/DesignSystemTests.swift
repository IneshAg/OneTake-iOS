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
}
