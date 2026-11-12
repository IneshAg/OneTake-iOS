import SwiftUI

public struct OTBottomBarModifier<Bar: View>: ViewModifier {
    private let bar: () -> Bar

    public init(@ViewBuilder bar: @escaping () -> Bar) {
        self.bar = bar
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: OTSpace.s) {
                    bar()
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.m)
                .padding(.bottom, OTSpace.s)
                .background(
                    OT.bgCanvas
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: Color.black.opacity(0.25), radius: 12, y: -4)
                )
            }
    }
}

public extension View {
    func otBottomBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
        modifier(OTBottomBarModifier(bar: bar))
    }
}
