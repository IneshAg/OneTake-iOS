import SwiftUI
import OneTakeUI

// MARK: - Record button (v2/Record Button · Ready / Rolling-hold)

/// Tap to start. While rolling it becomes hold-to-stop (0.8 s) so a stray tap can't end a take.
struct RecordButton: View {
    var isRecording: Bool
    var holdToStop: Bool = false
    var action: () -> Void
    @State private var holdProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4) // ot-lint:allow
                .frame(width: 78, height: 78) // ot-lint:allow

            if isRecording && holdToStop {
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(OT.recRed, style: StrokeStyle(lineWidth: 4, lineCap: .round)) // ot-lint:allow
                    .rotationEffect(.degrees(-90))
                    .frame(width: 78, height: 78) // ot-lint:allow
            }

            RoundedRectangle(cornerRadius: isRecording ? OTRadius.s : OTRadius.xl, style: .continuous)
                .fill(OT.recRed)
                .frame(width: isRecording ? 30 : 64, height: isRecording ? 30 : 64) // ot-lint:allow
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRecording)
        .contentShape(Circle())
        .onTapGesture {
            if !(isRecording && holdToStop) {
                if isRecording {
                    Haptics.impact(.medium)
                } else {
                    Haptics.impact(.heavy)
                }
                action()
            }
        }
        .onLongPressGesture(minimumDuration: 0.8, perform: {
            if isRecording && holdToStop {
                holdProgress = 0
                Haptics.impact(.medium)
                action()
            }
        }, onPressingChanged: { pressing in
            guard isRecording && holdToStop else { return }
            if pressing { Haptics.tick() }
            withAnimation(pressing ? .linear(duration: 0.8) : .easeOut(duration: 0.2)) {
                holdProgress = pressing ? 1 : 0
            }
        })
        .accessibilityLabel(isRecording ? (holdToStop ? "Stop recording, press and hold" : "Stop recording") : "Record")
        .accessibilityAddTraits(.isButton)
    }
}
