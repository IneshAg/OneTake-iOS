import SwiftUI
import OneTakeUI
import AVKit
import Speech

// MARK: - 13c Before you roll
// Solo-only for MVP: the solo/multi-device picker and the whole pairing flow are cut. Framing is
// checked after the fact by Tape Check, and the prompter is the solo flow's own, below.

struct ShootSetupView: View {
    let auditionID: Audition.ID
    /// The scene to shoot, when the actor came from a particular one; otherwise the next one due.
    var scene: Int? = nil
    @Environment(AppStore.self) private var store
    @AppStorage("speech.recognitionLocale") private var speechRecognitionLocale = SpeechFollower.defaultAccentIdentifier
    @AppStorage("camera.voiceCommandsEnabled") private var voiceCommandsEnabled = true
    @AppStorage("camera.gesturesEnabled") private var gesturesEnabled = false

    private var shootScene: Int { scene ?? store.sceneToShoot(auditionID) }
    /// Focus/Do Not Disturb can't be read or set by an app, so this one is the actor's own tick.
    @State private var silenced = false

    private struct Check {
        var eyebrow: String
        var title: String
        var detail: String
        var ok: Bool
    }

    /// Every row reflects the real state of this iPhone right now — nothing is assumed.
    private var checks: [Check] {
        var checks: [Check] = []

        if voiceCommandsEnabled {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                checks.append(Check(eyebrow: "Voice", title: "Say “Action” to start and “Cut” to stop",
                                    detail: "", ok: true))
            case .notDetermined:
                checks.append(Check(eyebrow: "Voice", title: "Allow speech access when prompted",
                                    detail: "Then say “Action” or “Cut” while filming.", ok: true))
            default:
                checks.append(Check(eyebrow: "Voice", title: "Voice commands are unavailable",
                                    detail: "Enable Speech Recognition in Settings, or use gestures / on-screen controls.", ok: false))
            }
        }
        if gesturesEnabled {
            checks.append(Check(eyebrow: "Gesture", title: "Hold an open palm toward the camera",
                                detail: "Starts, pauses, or resumes. Tap Record to finish a take.", ok: true))
        }

        if AVAudioApplication.shared.recordPermission == .denied {
            checks.append(Check(eyebrow: "Microphone", title: "Microphone access is off",
                                detail: "Enable it in Settings.", ok: false))
        } else {
            let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
            let isHeadset = input.map { [.bluetoothHFP, .headsetMic].contains($0.portType) } ?? false
            let micName: String
            switch input?.portType {
            case .some(.builtInMic): micName = "iPhone microphone"
            case .some(.bluetoothHFP), .some(.bluetoothLE): micName = "Bluetooth microphone"
            case .some(.headsetMic): micName = "Headset microphone"
            case .some(.usbAudio), .some(.lineIn): micName = "External microphone"
            default: micName = "iPhone microphone"
            }
            checks.append(Check(eyebrow: "Microphone", title: micName,
                                detail: isHeadset ? "" : "Stay near the phone.", ok: true))
        }

        _ = store.readerTrackVersion
        if let a = store.audition(auditionID), a.scenes.indices.contains(shootScene) {
            let readerLines = a.scenes[shootScene].lines.filter { !$0.isMine }
            let readerName = readerLines.first?.character.capitalized ?? "Reader"
            let specificReaderLines = readerLines.filter { $0.character.caseInsensitiveCompare(readerName) == .orderedSame }
            let recorded = specificReaderLines.indices.filter {
                ReaderTrackPlayer.hasRecording(auditionID: auditionID, sceneIndex: shootScene, line: $0)
            }.count
            if !specificReaderLines.isEmpty {
                checks.append(Check(eyebrow: "Reader", title: "\(recorded) of \(specificReaderLines.count) reader lines recorded",
                                    detail: recorded == specificReaderLines.count ? "" : "Record the missing lines for playback.",
                                    ok: recorded == specificReaderLines.count))
            }
        }

        checks.append(Check(eyebrow: "Interruptions", title: silenced ? "Silenced for this shoot" : "Calls and alerts can cut in",
                            detail: silenced ? "" : "Turn on Do Not Disturb in Control Centre.", ok: silenced))
        return checks
    }

    var body: some View {
        let rows = checks
        let audition = store.audition(auditionID)
        let sceneTitle = audition.flatMap {
            $0.scenes.indices.contains(shootScene) ? $0.scenes[shootScene].title : nil
        } ?? "Scene \(shootScene + 1)"

        OTScreen(title: "Scene setup", backLabel: "Back", onBack: { store.pop() }) {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                Text(sceneTitle).font(.otLargeTitle)
                Text("Check your reader and microphone before recording this scene.")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)

                VStack(alignment: .leading, spacing: OTSpace.s) {
                    Text("Hands-free controls")
                        .font(.otFootnote.weight(.semibold))
                    Toggle("Voice: say Action / Cut", isOn: $voiceCommandsEnabled)
                    Toggle("Gestures: open palm", isOn: $gesturesEnabled)
                    Text("Choose either control or turn on both. You can change these again in Camera Check.")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(OTSpace.cardInset)
                .otCard(.grouped)

                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Text("Speech accent")
                        .font(.otFootnote.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    Picker("Speech accent", selection: $speechRecognitionLocale) {
                        ForEach(SpeechFollower.availableEnglishAccents) { accent in
                            Text(accent.title).tag(accent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Choose the English accent closest to your pronunciation.")
                        .font(.otCaption)
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(OTSpace.cardInset)
                .otCard(.grouped)

                ForEach(rows, id: \.title) { c in
                    check(c.eyebrow, c.title, c.detail, ok: c.ok)
                    if c.eyebrow == "Reader", !c.ok {
                        Button {
                            store.push(.recordReader(auditionID, sceneIndex: shootScene))
                        } label: {
                            Label("Record the reader", systemImage: "mic")
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                    if c.eyebrow == "Interruptions", !silenced {
                        Button {
                            silenced = true
                            Haptics.success()
                        } label: {
                            Label("I've turned on Do Not Disturb", systemImage: "moon.fill")
                        }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                    }
                }
            }
        }
        .otBottomBar {
            Button {
                store.camera = .shoot(auditionID, scene: shootScene)
            } label: {
                Label("Open the camera", systemImage: "camera.fill")
            }
            .buttonStyle(.otPrimary)
        }
        .onAppear {
            if !SpeechFollower.availableEnglishAccents.contains(where: { $0.id == speechRecognitionLocale }) {
                speechRecognitionLocale = SpeechFollower.defaultAccentIdentifier
            }
        }
    }

    private func check(_ eyebrow: String, _ title: String, _ detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: OTSpace.m) {
            Circle()
                .fill(ok ? OT.accent : OT.warning)
                .frame(width: 8, height: 8) // ot-lint:allow
                .padding(.top, 6) // ot-lint:allow
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Text(title).font(.otHeadline)
                if !ok && !detail.isEmpty {
                    Text(detail).font(.otFootnote).foregroundStyle(OT.warning)
                }
            }
            Spacer()
        }
        .padding(.vertical, OTSpace.xxs)
    }
}
