import SwiftUI

public struct OTPressStyle: ButtonStyle {
    public enum Kind: Sendable {
        case card
        case nav
        case icon
    }

    public let kind: Kind

    public init(_ kind: Kind = .card) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .card:
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        case .nav:
            configuration.label
                .opacity(configuration.isPressed ? 0.65 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        case .icon:
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
