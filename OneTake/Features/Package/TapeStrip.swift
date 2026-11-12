import SwiftUI

struct TapeStrip: View {
    let legend: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            GeometryReader { geo in
                HStack(spacing: 3) { // ot-lint:allow
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: OTRadius.s)
                            .fill(item.2)
                            .frame(width: max(10, geo.size.width / CGFloat(max(legend.count, 1)) - 3)) // ot-lint:allow
                    }
                }
            }
            .frame(height: 44) // ot-lint:allow
            HStack(spacing: OTSpace.m) {
                ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                    legendItem(item.0, item.1, item.2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tape order: " + legend.map { "\($0.0), \($0.1)" }.joined(separator: ", "))
    }

    private func legendItem(_ t: String, _ d: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) { // ot-lint:allow
            HStack(spacing: OTSpace.xs) {
                RoundedRectangle(cornerRadius: 2) // ot-lint:allow
                    .fill(c)
                    .frame(width: 8, height: 8) // ot-lint:allow
                Text(t).font(.otCaption.weight(.semibold))
            }
            Text(d).font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
    }
}
