import SwiftUI

struct TapeStrip: View {
    let legend: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            GeometryReader { geo in
                HStack(spacing: OTSpace.xs) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        let segmentWidth = max(44, (geo.size.width - CGFloat(max(legend.count - 1, 0)) * OTSpace.xs) / CGFloat(max(legend.count, 1)))
                        VStack(spacing: OTSpace.xxs) {
                            Text(shortSegmentLabel(item.0))
                                .font(.otCaption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(item.1)
                                .font(.otCaption)
                                .opacity(0.88)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(OT.labelOnAccent)
                        .padding(.horizontal, OTSpace.xs)
                        .frame(width: segmentWidth, height: 48) // ot-lint:allow
                        .background(
                            RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous)
                                .fill(item.2)
                        )
                    }
                }
            }
            .frame(height: 48) // ot-lint:allow
            HStack(spacing: OTSpace.m) {
                ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                    legendItem(item.0, item.1, item.2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tape order: " + legend.map { "\($0.0), \($0.1)" }.joined(separator: ", "))
    }

    private func shortSegmentLabel(_ title: String) -> String {
        if title.caseInsensitiveCompare("Headshots") == .orderedSame { return "Photos" }
        if title.caseInsensitiveCompare("Full-body shot") == .orderedSame || title.caseInsensitiveCompare("Full length") == .orderedSame {
            return "Full"
        }
        return title
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
