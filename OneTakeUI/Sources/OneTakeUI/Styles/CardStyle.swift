import SwiftUI

public enum OTCardKind: Sendable {
    /// surfaceCard with soft drop shadow, radius 24 pt
    case elevated
    /// fillField with continuous corners, radius 16 pt
    case grouped
    /// sunken/subtle background, radius 12 pt
    case inset
}

public struct OTCardModifier: ViewModifier {
    public let kind: OTCardKind
    public let padding: CGFloat?

    public init(_ kind: OTCardKind = .elevated, padding: CGFloat? = OTSpace.cardInset) {
        self.kind = kind
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let contentWithPadding = Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }

        switch kind {
        case .elevated:
            contentWithPadding
                .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: OTRadius.card, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        case .grouped:
            contentWithPadding
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
        case .inset:
            contentWithPadding
                .background(OT.bgCanvas.opacity(0.55), in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous))
        }
    }
}

public struct CardBackground: ViewModifier {
    public var radius: CGFloat = OT.cardRadius
    public init(radius: CGFloat = OT.cardRadius) {
        self.radius = radius
    }
    public func body(content: Content) -> some View {
        content
            .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
    }
}

public extension View {
    func otCard(_ kind: OTCardKind = .elevated, padding: CGFloat? = OTSpace.cardInset) -> some View {
        modifier(OTCardModifier(kind, padding: padding))
    }

    @available(*, deprecated, message: "Use otCard(_ kind:padding:) instead")
    func otCard(radius: CGFloat = OT.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}
