import SwiftUI

struct HeadshotSlotTile: View {
    let title: String
    let done: Bool
    let big: Bool
    var auditionID: Audition.ID?
    var onAdjust: () -> Void
    var onInspect: () -> Void
    var onPick: () -> Void

    private var key: String {
        title == "Front" ? "front" : title == "Left profile" ? "left" : "right"
    }
    private var isProfile: Bool {
        key == "left" || key == "right"
    }

    var body: some View {
        if done {
            ZStack(alignment: .bottomLeading) {
                HeadshotImage(realKey: key, auditionID: auditionID)
                    .contentShape(Rectangle())
                    .onTapGesture { onInspect() }

                LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .center, endPoint: .bottom) // ot-lint:allow
                    .allowsHitTesting(false)

                HStack {
                    Label(title, systemImage: "checkmark")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onAdjust) {
                        HStack(spacing: OTSpace.xxs) {
                            Image(systemName: "crop")
                                .font(.otIcon(.s, weight: .bold))
                            Text("Adjust")
                                .font(.otCaptionStrong)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, OTSpace.s)
                        .padding(.vertical, OTSpace.xs)
                        .background(OT.cameraGlass, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .otHitArea()
                }
                .padding(OTSpace.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: OTRadius.xl, style: .continuous))
        } else {
            Button(action: onPick) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: OTRadius.xl, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(OT.labelTertiary)
                    VStack(spacing: OTSpace.xs) {
                        Image(systemName: "photo.badge.plus")
                            .font(.otIcon(big ? .xxl : .xl))
                            .foregroundStyle(OT.accent)
                        Text(title)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text("Pick from Photos")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: OTRadius.xl, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: OTRadius.xl, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
