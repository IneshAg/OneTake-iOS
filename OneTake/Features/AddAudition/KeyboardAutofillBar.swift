import SwiftUI
import OneTakeUI

struct KeyboardAutofillBar: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    let onDone: () -> Void

    var body: some View {
        HStack(spacing: OTSpace.m) {
            if suggestions.isEmpty {
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: OTSpace.m) {
                        ForEach(suggestions.prefix(6), id: \.self) { item in
                            Button {
                                Haptics.tick()
                                onSelect(item)
                            } label: {
                                Text(item)
                                    .font(.otSubhead)
                                    .foregroundStyle(OT.labelPrimary)
                                    .lineLimit(1)
                                    .padding(.horizontal, OTSpace.xs)
                                    .frame(minHeight: OTControlSize.small.hitHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Divider()
                    .frame(height: OTSpace.xl)
            }

            Button("Done", action: onDone)
                .font(.otSubhead.weight(.semibold))
                .fixedSize()
        }
    }
}

/// Kept for backward compatibility
struct SuggestionChipBar: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        EmptyView()
    }
}
