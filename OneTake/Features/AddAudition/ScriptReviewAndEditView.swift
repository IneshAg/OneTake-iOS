import SwiftUI
import OneTakeUI

// MARK: - Interactive Script Review & 1-Tap Line Editor ("Magic Highlighter")

struct ScriptReviewAndEditView: View {
    @Binding var scenes: [ScriptScene]
    @State private var editingLine: (sceneIndex: Int, lineIndex: Int)?
    @State private var editedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.m) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { sIdx, scene in
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    HStack {
                        Text(scene.heading)
                            .font(.otSubhead.weight(.bold))
                            .foregroundStyle(OT.accent)
                        Spacer()
                        Text("\(scene.lines.count) lines · ≈ \(scene.estimatedSeconds / 60):\(String(format: "%02d", scene.estimatedSeconds % 60))")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    .padding(.bottom, OTSpace.xxs)

                    ForEach(Array(scene.lines.enumerated()), id: \.element.id) { lIdx, line in
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            HStack(alignment: .center, spacing: OTSpace.s) {
                                // 1-Tap Role Toggle Pill
                                Button {
                                    toggleSpeaker(sceneIndex: sIdx, lineIndex: lIdx)
                                    Haptics.tick()
                                } label: {
                                    HStack(spacing: OTSpace.xs) {
                                        Image(systemName: line.isMine ? "person.crop.circle.fill" : "person.2.fill")
                                            .font(.otCaption.weight(.bold))
                                        Text(line.isMine ? "\(line.character) (YOU)" : "\(line.character)")
                                            .font(.otCaption.weight(.bold))
                                    }
                                    .padding(.horizontal, OTSpace.s)
                                    .padding(.vertical, OTSpace.xs)
                                    .background(
                                        Capsule()
                                            .fill(line.isMine ? OT.accentSoft : OT.reader.opacity(0.15))
                                            .overlay(
                                                Capsule().stroke(line.isMine ? OT.accent.opacity(0.35) : OT.reader.opacity(0.35), lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(line.isMine ? OT.accent : OT.reader)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                // Merge with above button (if not first line)
                                if lIdx > 0 {
                                    Button {
                                        mergeWithAbove(sceneIndex: sIdx, lineIndex: lIdx)
                                        Haptics.tick()
                                    } label: {
                                        Image(systemName: "arrow.turn.left.up")
                                            .font(.otCaption.weight(.semibold))
                                            .foregroundStyle(OT.labelTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Merge with above line")
                                }

                                // Delete line button
                                Button {
                                    deleteLine(sceneIndex: sIdx, lineIndex: lIdx)
                                    Haptics.tick()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.otCaption.weight(.medium))
                                        .foregroundStyle(OT.labelTertiary.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete line")
                            }

                            // Editable Line Text
                            if line.isSilentReactionCue {
                                Button {
                                    editingLine = (sIdx, lIdx)
                                    editedText = line.text
                                } label: {
                                    SilentReactionCue(cueText: line.text, isMine: line.isMine, inPrompter: false)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(line.text)
                                    .font(.otBody)
                                    .foregroundStyle(OT.labelPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(OTSpace.s)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                            .fill(line.isMine ? OT.accentSoft.opacity(0.35) : OT.fillField)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                            .stroke(line.isMine ? OT.accent.opacity(0.25) : OT.separator.opacity(0.5), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        editingLine = (sIdx, lIdx)
                                        editedText = line.text
                                    }
                            }
                        }
                        .padding(.vertical, OTSpace.xxs)
                    }
                }
                .otCard(.elevated)
            }
        }
        .sheet(item: Binding(
            get: { editingLine.map { EditLinePayload(sceneIndex: $0.sceneIndex, lineIndex: $0.lineIndex) } },
            set: { if $0 == nil { editingLine = nil } }
        )) { payload in
            NavigationStack {
                VStack(spacing: OTSpace.l) {
                    Text("Edit Line Text")
                        .font(.otHeadline)
                        .padding(.top, OTSpace.l)

                    TextEditor(text: $editedText)
                        .foregroundStyle(OT.labelPrimary)
                        .tint(OT.accent)
                        .padding(OTSpace.s)
                        .scrollContentBackground(.hidden)
                        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: OTRadius.m)) // ot-lint:allow
                        .frame(minHeight: 120) // ot-lint:allow

                    HStack(spacing: OTSpace.m) {
                        Button("Cancel") {
                            editingLine = nil
                        }
                        .buttonStyle(.ot(.secondary, size: .medium))

                        Button("Save") {
                            if scenes.indices.contains(payload.sceneIndex),
                               scenes[payload.sceneIndex].lines.indices.contains(payload.lineIndex) {
                                scenes[payload.sceneIndex].lines[payload.lineIndex].text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            editingLine = nil
                            Haptics.success()
                        }
                        .buttonStyle(.ot(.primary, size: .medium))
                    }
                    .padding(.horizontal, OTSpace.l)

                    Spacer()
                }
                .padding(OTSpace.l)
                .preferredColorScheme(.dark)
            }
            .presentationDetents([.height(300)]) // ot-lint:allow
        }
    }

    private func toggleSpeaker(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex) else { return }
        scenes[sceneIndex].lines[lineIndex].isMine.toggle()
    }

    private func deleteLine(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex) else { return }
        scenes[sceneIndex].lines.remove(at: lineIndex)
    }

    private func mergeWithAbove(sceneIndex: Int, lineIndex: Int) {
        guard scenes.indices.contains(sceneIndex),
              scenes[sceneIndex].lines.indices.contains(lineIndex),
              lineIndex > 0 else { return }
        let current = scenes[sceneIndex].lines[lineIndex]
        scenes[sceneIndex].lines[lineIndex - 1].text += " " + current.text
        scenes[sceneIndex].lines.remove(at: lineIndex)
    }
}

private struct EditLinePayload: Identifiable {
    var id: String { "\(sceneIndex)_\(lineIndex)" }
    let sceneIndex: Int
    let lineIndex: Int
}
