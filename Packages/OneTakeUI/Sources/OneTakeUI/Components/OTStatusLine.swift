import SwiftUI

public enum OTStatusKind: Sendable {
    case progress
    case success
    case failure
    case offline
    case due

    public static let saving = OTStatusKind.progress
    public static let processing = OTStatusKind.progress
    public static let uploading = OTStatusKind.progress
    public static let delivered = OTStatusKind.success
    public static let failed = OTStatusKind.failure
}

public struct OTStatusLine: View {
    public let kind: OTStatusKind
    public let text: String
    public let detail: String?

    public init(_ kind: OTStatusKind, _ text: String, detail: String? = nil) {
        self.kind = kind
        self.text = text
        self.detail = detail
    }

    public init(kind: OTStatusKind, text: String) {
        self.kind = kind
        self.text = text
        self.detail = nil
    }

    private var icon: some View {
        Group {
            switch kind {
            case .progress:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.otIcon(.m))
                    .foregroundStyle(OT.success)
            case .failure:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.otIcon(.m))
                    .foregroundStyle(OT.danger)
            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.otIcon(.m))
                    .foregroundStyle(OT.warning)
            case .due:
                Image(systemName: "clock")
                    .font(.otIcon(.m))
                    .foregroundStyle(OT.due)
            }
        }
    }

    private var textColor: Color {
        switch kind {
        case .due: return OT.due
        default: return OT.labelPrimary
        }
    }

    public var body: some View {
        HStack(spacing: OTSpace.s) {
            icon
            Text(text)
                .font(.otSubhead)
                .foregroundStyle(textColor)
            if let detail {
                Text("· \(detail)")
                    .font(.otCaption)
                    .foregroundStyle(OT.labelSecondary)
            }
        }
    }
}
