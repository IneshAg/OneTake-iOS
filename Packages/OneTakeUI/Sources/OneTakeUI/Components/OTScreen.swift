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

    public var body: some View {
        VStack(spacing: 0) {
            OTNavHeader(title: title, backLabel: backLabel, onBack: onBack, trailing: trailing)
                .padding(.horizontal, OTSpace.m)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.s)
                .background(OT.bgCanvas)

            if scrolls {
                ScrollView {
                    content()
                        .padding(.horizontal, OTSpace.m)
                        .padding(.bottom, OTSpace.xl)
                }
            } else {
                content()
                    .padding(.horizontal, OTSpace.m)
                    .padding(.bottom, OTSpace.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .otCanvas()
        .toolbarVisibility(.hidden, for: .tabBar) // ot-lint:allow
        .toolbar(.hidden, for: .tabBar) // ot-lint:allow
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow sole container allowed to hide navigationBar
        .navigationBarBackButtonHidden(true)
        .background(TabBarHider())
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
