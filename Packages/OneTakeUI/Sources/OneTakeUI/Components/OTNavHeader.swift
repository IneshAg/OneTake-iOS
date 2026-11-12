import SwiftUI

public struct OTNavHeader<Trailing: View>: View {
    public let title: String
    public let backLabel: String
    public let onBack: (() -> Void)?
    public let onDark: Bool
    private let trailing: () -> Trailing

    @Environment(\.otSurface) private var otSurface: OTSurface
    @Environment(\.dismiss) private var dismiss

    public init(
        title: String = "",
        backLabel: String = "Back",
        onDark: Bool = false,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.backLabel = backLabel
        self.onDark = onDark
        self.onBack = onBack
        self.trailing = trailing
    }

    private var effectiveSurface: OTSurface {
        onDark ? .camera : otSurface
    }

    private var handleBack: () -> Void {
        onBack ?? { dismiss() }
    }

    private var isDismissStyle: Bool {
        backLabel.caseInsensitiveCompare("Cancel") == .orderedSame ||
        backLabel.caseInsensitiveCompare("Done") == .orderedSame
    }

    private var isCloseStyle: Bool {
        backLabel.caseInsensitiveCompare("Close") == .orderedSame
    }

    public var body: some View {
        HStack(spacing: OTSpace.m) {
            // Leading
            if isDismissStyle {
                Button(action: {
                    Haptics.tick()
                    handleBack()
                }) {
                    Text(backLabel)
                        .font(.body)
                        .foregroundStyle(effectiveSurface == .camera ? OT.cameraLabel : OT.accent)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isCloseStyle {
                OTIconButton("xmark", accessibilityLabel: "Close", action: handleBack)
            } else {
                OTIconButton("chevron.left", accessibilityLabel: backLabel.isEmpty ? "Back" : backLabel, action: handleBack)
            }

            // Center Title
            Text(title)
                .font(.headline)
                .foregroundStyle(effectiveSurface == .camera ? OT.cameraLabel : OT.labelPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // Trailing
            trailing()
                .frame(minWidth: 44, alignment: .trailing)
                .frame(height: 44)
        }
        .frame(height: 44)
    }
}

public extension OTNavHeader where Trailing == EmptyView {
    init(
        title: String = "",
        backLabel: String = "Back",
        onDark: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.init(title: title, backLabel: backLabel, onDark: onDark, onBack: onBack, trailing: { EmptyView() })
    }
}


