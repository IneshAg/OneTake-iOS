import SwiftUI

// MARK: - Typography (Dynamic Type scaling)

public extension Font {
    static let otLargeTitle     = Font.largeTitle.bold()
    static let otTitle          = Font.title.bold()
    static let otHero           = Font.largeTitle.bold()
    static let otHeadline       = Font.headline
    static let otBody           = Font.body
    static let otCallout        = Font.subheadline
    static let otSubhead        = Font.subheadline.weight(.medium)
    static let otFootnote       = Font.footnote
    static let otCaption        = Font.caption
    static let otEyebrow        = Font.footnote.weight(.semibold)
    static let otNumber         = Font.largeTitle.bold().monospacedDigit()
    static let otButtonSmall    = Font.subheadline.weight(.semibold)
    static let otCaptionStrong  = Font.caption.weight(.semibold)
}
