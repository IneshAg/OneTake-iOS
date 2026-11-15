import SwiftUI
import OneTakeUI

/// Unified bottom control dock for `PracticeTakeView` (both Camera & Voice modes).
/// Brings Pause/Resume, Stop/Finish, and line navigation together within thumb reach so actors
/// never have to hunt for controls across full-screen overlays.
struct PracticeRecordingDock: View {
    let recordMode: PracticeRecordMode
    let cameraState: CameraController.State
    let isExposureLocked: Bool
    let prompterSize: Int
    let hasLines: Bool
    let isAtLastLine: Bool
    let rehearsalFinished: Bool

    var onPreviousLine: () -> Void
    var onNextLine: () -> Void
    var onRestartLines: () -> Void
    var onCycleSize: () -> Void
    var onToggleAE: () -> Void
    var onStartRecording: () -> Void
    var onPauseResume: () -> Void
    var onStopRecording: () -> Void

    private var isActiveSession: Bool {
        cameraState == .recording || cameraState == .paused
    }

    var body: some View {
        VStack(spacing: OTSpace.s) {
            if hasLines && (isActiveSession || rehearsalFinished) {
                HStack(spacing: OTSpace.s) {
                    if rehearsalFinished {
                        Button(action: onRestartLines) {
                            Label("Restart lines", systemImage: "arrow.counterclockwise")
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.cameraLabel)
                                .padding(.horizontal, OTSpace.m)
                                .frame(height: 36) // ot-lint:allow
                                .background(OT.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onPreviousLine) {
                            Image(systemName: "chevron.left")
                                .font(.otFootnote.weight(.bold))
                                .foregroundStyle(OT.cameraLabel)
                                .frame(width: 36, height: 36) // ot-lint:allow
                                .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous line")

                        Button(action: onNextLine) {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: isAtLastLine ? "checkmark" : "arrow.right")
                                    .font(.otCaption.weight(.bold))
                                Text(isAtLastLine ? "Finish lines" : "Next line")
                                    .font(.otFootnote.weight(.semibold))
                            }
                            .foregroundStyle(OT.cameraLabel)
                            .padding(.horizontal, OTSpace.m)
                            .frame(height: 36) // ot-lint:allow
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onCycleSize) {
                        HStack(spacing: OTSpace.xs) {
                            Image(systemName: "textformat.size").font(.otCaption)
                            Text(["Regular", "Big", "Huge"][min(max(prompterSize, 0), 2)])
                                .font(.otCaption.weight(.bold))
                        }
                        .foregroundStyle(OT.cameraLabel)
                        .padding(.horizontal, OTSpace.s)
                        .frame(height: 36) // ot-lint:allow
                        .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if recordMode == .camera {
                        Button(action: onToggleAE) {
                            HStack(spacing: OTSpace.xs) {
                                Image(systemName: isExposureLocked ? "lock.fill" : "lock.open")
                                    .font(.otCaption)
                                Text(isExposureLocked ? "Locked" : "AE")
                                    .font(.otCaption.weight(.bold))
                            }
                            .foregroundStyle(isExposureLocked ? OT.prompterGold : OT.cameraLabel)
                            .padding(.horizontal, OTSpace.s)
                            .frame(height: 36) // ot-lint:allow
                            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.s, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isActiveSession {
                HStack(spacing: OTSpace.l) {
                    Button(action: onPauseResume) {
                        HStack(spacing: OTSpace.xs) {
                            Image(systemName: cameraState == .paused ? "play.fill" : "pause.fill")
                            Text(cameraState == .paused ? "Resume" : "Pause")
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.cameraLabel)
                        .padding(.horizontal, OTSpace.l)
                        .frame(height: OT.minTap) // ot-lint:allow
                        .background(
                            Capsule().fill(cameraState == .paused ? OT.accent : OT.cameraGlass)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cameraState == .paused ? "Resume recording" : "Pause recording")

                    Button(action: onStopRecording) {
                        HStack(spacing: OTSpace.xs) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.otSubhead.weight(.bold))
                        .foregroundStyle(OT.cameraLabel)
                        .padding(.horizontal, OTSpace.l)
                        .frame(height: OT.minTap) // ot-lint:allow
                        .background(
                            Capsule().fill(OT.recRed)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop and save recording")
                }
                .padding(.horizontal, OTSpace.m)
                .padding(.vertical, OTSpace.s)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(OT.cameraStroke, lineWidth: 1))
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if recordMode == .voiceOnly {
                VStack(spacing: OTSpace.xs) {
                    Button(action: onStartRecording) {
                        ZStack {
                            Circle()
                                .fill(OT.cameraGlass)
                                .frame(width: 76, height: 76) // ot-lint:allow
                                .overlay(Circle().stroke(OT.cameraStroke, lineWidth: 2))
                            Image(systemName: "mic.fill")
                                .font(.otTitle)
                                .foregroundStyle(OT.recRed)
                        }
                    }
                    .buttonStyle(OTPressStyle(.icon))
                    .accessibilityLabel("Start voice recording")

                    Label("Voice rehearsal · no camera", systemImage: "mic.fill")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.cameraLabel2)
                }
            } else {
                RecordButton(isRecording: false, action: onStartRecording)
            }
        }
        .padding(.bottom, OTSpace.m)
        .animation(OTMotion.snappy, value: cameraState)
    }
}
