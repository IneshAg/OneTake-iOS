import SwiftUI
import UIKit

public enum OTIconSize: CGFloat, CaseIterable {
    case xs   = 11
    case s    = 13
    case m    = 15
    case l    = 17
    case xl   = 22
    case xxl  = 28
    case hero = 40
}

public extension Font {
    static func otIcon(_ size: OTIconSize, weight: Font.Weight = .semibold) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size.rawValue)
        return Font.system(size: scaled, weight: weight)
    }
}
