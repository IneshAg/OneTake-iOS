import SwiftUI
import OneTakeUI

// MARK: - Record button (v2/Record Button · Ready / Rolling-hold)

/// Tap to start. While rolling it becomes hold-to-stop (0.8 s) so a stray tap can't end a take.
struct RecordButton: View {
    var isRecording: Bool
    var holdToStop: Bool = false
    var action: () -> Void
    @Environment(\.otSurface) private var otSurface
    @Environment(\.colorScheme) private var colorScheme
    @State private var holdProgress: CGFloat = 0
    @State private var isPressed = false

    private var ringColor: Color {
        (otSurface == .camera || colorScheme == .dark)
            ? Color.white // ot-lint:allow
            : Color.secondary.opacity(0.35) // ot-lint:allow
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor, lineWidth: 3.5) // ot-lint:allow
                .frame(width: 74, height: 74) // ot-lint:allow

            if isRecording && holdToStop {
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(OT.recRed, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)) // ot-lint:allow
                    .rotationEffect(.degrees(-90))
                    .frame(width: 74, height: 74) // ot-lint:allow
            }

            RoundedRectangle(cornerRadius: isRecording ? OTRadius.s : 30, style: .continuous) // ot-lint:allow
                .fill(OT.recRed)
                .frame(width: isRecording ? 28 : 60, height: isRecording ? 28 : 60) // ot-lint:allow
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isRecording)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
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
