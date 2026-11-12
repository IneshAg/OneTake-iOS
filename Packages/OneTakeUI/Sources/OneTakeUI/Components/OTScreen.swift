import SwiftUI

public struct OTScreen<Content: View, Trailing: View>: View {
    public let title: String
    public let backLabel: String
    public let onBack: (() -> Void)?
    public let scrolls: Bool
    private let trailing: () -> Trailing
    private let content: () -> Content

    public init(
        title: String = "",
        backLabel: String = "Back",
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.backLabel = backLabel
        self.onBack = onBack
        self.scrolls = scrolls
        self.trailing = trailing
        self.content = content
    }

    @ViewBuilder
    private var innerContent: some View {
        VStack(alignment: .leading, spacing: OTSpace.l) {
            OTNavHeader(title: title, backLabel: backLabel, onBack: onBack, trailing: trailing)
            content()
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.bottom, OTSpace.xl)
    }

    public var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    innerContent
                }
            } else {
                innerContent
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow sole container allowed to hide navigationBar
        .navigationBarBackButtonHidden(true)
    }
}

public extension OTScreen where Trailing == EmptyView {
    init(
        title: String = "",
        backLabel: String = "Back",
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, backLabel: backLabel, onBack: onBack, scrolls: scrolls, trailing: { EmptyView() }, content: content)
    }
}
