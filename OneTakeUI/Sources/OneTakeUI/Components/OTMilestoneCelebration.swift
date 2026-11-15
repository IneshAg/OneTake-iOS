import SwiftUI

/// Data model for transient celebration feedback banners shown when an actor hits a milestone.
public struct OTMilestoneBannerItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let systemImage: String

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        systemImage: String = "checkmark.seal.fill"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }
}

/// Floating pill celebration banner with a spring pop badge and optional Sparkle ring burst.
public struct OTMilestoneBanner: View {
    public let item: OTMilestoneBannerItem
    public var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.otSurface) private var otSurface
    @State private var popped = false

    public init(item: OTMilestoneBannerItem, onDismiss: (() -> Void)? = nil) {
        self.item = item
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let isDarkSurface = otSurface == .camera
        HStack(spacing: OTSpace.m) {
            ZStack {
                Circle()
                    .fill(OT.success.opacity(isDarkSurface ? 0.25 : 0.14))
                    .frame(width: 36, height: 36)
                    .scaleEffect(popped ? 1.0 : 0.6)
                Image(systemName: item.systemImage)
                    .font(.otIcon(.m, weight: .bold))
                    .foregroundStyle(OT.success)
                    .scaleEffect(popped ? 1.0 : 0.5)
                    .rotationEffect(.degrees(popped ? 0 : -14))
            }

            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text(item.title)
                    .font(.otSubhead.weight(.bold))
                    .foregroundStyle(isDarkSurface ? OT.cameraLabel : OT.labelPrimary)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.otCaption)
                        .foregroundStyle(isDarkSurface ? OT.cameraLabel2 : OT.labelSecondary)
                }
            }

            Spacer(minLength: OTSpace.xs)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.otCaption.weight(.bold))
                        .foregroundStyle(isDarkSurface ? OT.cameraLabel2 : OT.labelTertiary)
                        .padding(OTSpace.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, OTSpace.m)
        .padding(.vertical, OTSpace.s)
        .background(
            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                .fill(isDarkSurface ? OT.cameraBg.opacity(0.92) : OT.surfaceRaised)
                .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                .strokeBorder(OT.success.opacity(0.35), lineWidth: 1)
        )
        .onAppear {
            if reduceMotion {
                popped = true
            } else {
                withAnimation(OTMotion.bouncy) {
                    popped = true
                }
            }
        }
    }
}

public extension View {
    /// Overlays a top celebratory milestone banner that automatically slides in with spring motion.
    func otMilestoneBanner(_ item: Binding<OTMilestoneBannerItem?>) -> some View {
        overlay(alignment: .top) {
            if let current = item.wrappedValue {
                OTMilestoneBanner(item: current) {
                    withAnimation(OTMotion.snappy) {
                        item.wrappedValue = nil
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(OTMotion.bouncy, value: item.wrappedValue)
    }
}
