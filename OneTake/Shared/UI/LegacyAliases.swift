import SwiftUI

// MARK: - Legacy aliases for design system migration

typealias SectionLabel = OTSectionLabel
typealias ProgressRing = OTProgressRing
typealias ScheduleRow = OTScheduleRow
typealias InlineStatus = OTStatusLine
typealias SheetHeader = OTSheetHeader
typealias IconRow = OTIconRow
typealias InContentNavHeader = OTNavHeader

// MARK: - Navigation components (legacy compatibility)

struct GlassBackButton: View {
    var label: String = "Back"
    var onDark: Bool = false
    var action: () -> Void

    var body: some View {
        OTIconButton("chevron.left", accessibilityLabel: label, action: action)
            .otSurface(onDark ? .camera : .standard)
    }
}

struct GlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var onDark = false
    var action: () -> Void

    var body: some View {
        OTIconButton(systemName, accessibilityLabel: accessibilityLabel, action: action)
            .otSurface(onDark ? .camera : .standard)
    }
}

struct GlassButtonCompatibility: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                .buttonStyle(OTPressStyle(.nav))
        } else {
            content.buttonStyle(.plain)
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OTSpace.xxs) {
            configuration.title
            configuration.icon
        }
    }
}
