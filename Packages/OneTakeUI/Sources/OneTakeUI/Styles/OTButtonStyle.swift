import SwiftUI

public enum OTButtonVariant: String, CaseIterable, Sendable {
    case primary
    case secondary
    case tertiary
    case destructive
    case glass
}

public struct OTButtonStyle: ButtonStyle {
    public let variant: OTButtonVariant
    public let size: OTControlSize
    public let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled: Bool
    @Environment(\.otSurface) private var otSurface: OTSurface

    public init(
        _ variant: OTButtonVariant,
        size: OTControlSize = .large,
        fullWidth: Bool = true
    ) {
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
    }

    public static func foreground(for variant: OTButtonVariant, surface: OTSurface) -> Color {
        switch variant {
        case .primary:
            return OT.labelOnAccent
        case .secondary:
            return surface == .camera ? OT.cameraLabel : OT.labelPrimary
        case .tertiary:
            return surface == .camera ? OT.cameraLabel : OT.accent
        case .destructive:
            return OT.danger
        case .glass:
            return surface == .camera ? OT.cameraLabel : OT.accent
        }
    }

    private var radius: CGFloat {
        size == .small ? OTRadius.m : OTRadius.control
    }

    @ViewBuilder
    private func backgroundView(surface: OTSurface) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch variant {
        case .primary:
            shape.fill(isEnabled ? OT.accent : OT.accent.opacity(0.35))
        case .secondary:
            if surface == .camera {
                shape.fill(OT.cameraGlass)
            } else {
                shape.fill(OT.fillField)
            }
        case .tertiary:
            Color.clear
        case .destructive:
            shape.fill(OT.danger.opacity(0.12))
        case .glass:
            if surface == .camera {
                shape.fill(OT.cameraGlass)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            }
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        let fg = Self.foreground(for: variant, surface: otSurface)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        configuration.label
            .font(size.font)
            .foregroundStyle(fg)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
            .background(backgroundView(surface: otSurface))
            .contentShape(shape)
            .frame(minHeight: size.hitHeight)
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1.0 : 0.45))
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == OTButtonStyle {
    static func ot(_ variant: OTButtonVariant, size: OTControlSize = .large, fullWidth: Bool = true) -> OTButtonStyle {
        OTButtonStyle(variant, size: size, fullWidth: fullWidth)
    }

    static var otPrimary: OTButtonStyle {
        .ot(.primary)
    }

    static var otSecondary: OTButtonStyle {
        .ot(.secondary)
    }

    static var otCompact: OTButtonStyle {
        .ot(.secondary, size: .small, fullWidth: false)
    }

    static var otGlass: OTButtonStyle {
        .ot(.glass, size: .medium, fullWidth: false)
    }
}

public struct OTTrailingIconLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OTSpace.xxs) {
            configuration.title
            configuration.icon
        }
    }
}

public typealias TrailingIconLabelStyle = OTTrailingIconLabelStyle

public struct GlassButtonCompatibility: ViewModifier {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
    @ViewBuilder
    public func body(content: Content) -> some View {
        if enabled {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.7)) // ot-lint:allow
                .buttonStyle(OTPressStyle(.nav))
        } else {
            content.buttonStyle(.plain)
        }
    }
}
