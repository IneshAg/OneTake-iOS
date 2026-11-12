import SwiftUI

public struct OTGalleryView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.xl) {
                OTNavHeader(title: "OneTakeUI Gallery", backLabel: "Back", onBack: {}) {
                    OTIconButton("gear", accessibilityLabel: "Settings") {}
                }

                // Buttons
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    OTSectionLabel("Buttons — Large")
                    Button("Primary Action") {}.buttonStyle(.otPrimary)
                    Button("Secondary Action") {}.buttonStyle(.otSecondary)
                    Button("Destructive Action") {}.buttonStyle(.ot(.destructive))

                    OTSectionLabel("Buttons — Medium & Small")
                    HStack(spacing: OTSpace.s) {
                        Button("Medium Action") {}.buttonStyle(.ot(.secondary, size: .medium, fullWidth: false))
                        OTMenuButton("Menu Action", systemImage: "ellipsis", size: .medium, fullWidth: false) {
                            Button("Option 1") {}
                            Button("Option 2") {}
                        }
                    }

                    HStack(spacing: OTSpace.s) {
                        OTChip("Front", isSelected: true) {}
                        OTChip("Left profile", isSelected: false) {}
                        OTChip("Right profile", isSelected: false) {}
                    }
                }

                // Cards
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    OTSectionLabel("Cards & Callouts")

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Text("Elevated Card").font(.otHeadline)
                        Text("Default surfaceCard with soft drop shadow.").font(.otBody).foregroundStyle(OT.labelSecondary)
                    }
                    .otCard(.elevated)

                    OTCallout(
                        systemImage: "camera.fill",
                        title: "Saved for this audition",
                        message: "These photos stay on this iPhone and go with this tape."
                    )

                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Text("Inset Card").font(.otHeadline)
                        Text("Subtle inset background for secondary groupings.").font(.otBody).foregroundStyle(OT.labelSecondary)
                    }
                    .otCard(.inset)
                }

                // Status & Feedback
                VStack(alignment: .leading, spacing: OTSpace.m) {
                    OTSectionLabel("Status & Indicators")
                    OTStatusLine(.success, "Headshots saved on this iPhone", detail: "Next: slate")
                    OTStatusLine(.progress, "Processing tape...")
                    OTStatusLine(.failure, "Failed to export video", detail: "Tap to retry")

                    HStack(spacing: OTSpace.l) {
                        OTProgressRing(progress: 0.65)
                            .frame(width: 44, height: 44)
                        OTProgressRing(progress: 1.0)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.bottom, OTSpace.xxl)
        }
        .otCanvas()
    }
}

#Preview("Light Mode") {
    OTGalleryView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OTGalleryView()
        .preferredColorScheme(.dark)
}

#Preview("Camera Surface") {
    OTGalleryView()
        .otSurface(.camera)
        .preferredColorScheme(.dark)
}
