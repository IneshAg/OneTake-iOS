import SwiftUI
import OneTakeUI

struct KeyboardAutofillBar: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: OTSpace.s) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OTSpace.xs) {
                        ForEach(suggestions.prefix(6), id: \.self) { item in
                            Button {
                                Haptics.tick()
                                onSelect(item)
                            } label: {
                                HStack(spacing: OTSpace.xs) {
                                    Image(systemName: "sparkles")
                                        .font(.otIcon(.xs))
                                        .foregroundStyle(OT.accent)
                                    Text(item)
                                        .font(.otSubhead)
                                        .foregroundStyle(OT.labelPrimary)
                                }
                                .padding(.horizontal, OTSpace.s)
                                .padding(.vertical, OTSpace.xs)
                                .background(OT.fillField, in: Capsule()) // ot-lint:allow
                                .overlay(
                                    Capsule().stroke(OT.separator, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, OTSpace.xxs)
                }
            } else {
                Spacer()
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.accent)
                }
                .buttonStyle(.plain)
            }
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
