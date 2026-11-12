import SwiftUI

public struct OTSectionLabel: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.otEyebrow)
            .foregroundStyle(OT.labelTertiary)
    }
}
