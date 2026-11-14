import SwiftUI
import OneTakeUI

/// Step 2 of OCR Review: Portion selection (scenes / pages), "Matches role" tags, cue reader audio configuration.
struct ReviewStepScenesView: View {
    let portions: [ScriptParser.ScenePortion]
    let roleText: String
    let portionsArePages: Bool
    @Binding var selectedPortionIDs: Set<String>
    let hasReaderLines: Bool
    let detectedReaderName: String
    @Binding var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan

    @State private var preview: ScriptParser.ScenePortion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Text(portionsArePages ? "Pages to prepare" : "Scenes to prepare")
                        .font(.otTitle)
                    Text("Select the material casting asked you to prepare for \(roleText.isEmpty ? "your role" : roleText). Open a preview to check what each section contains.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }

                HStack {
                    Text("\(selectedPortionIDs.count) of \(portions.count) selected")
                        .font(.otCaption.weight(.medium))
                        .foregroundStyle(OT.labelSecondary)
                    Spacer()
                    Button(selectedPortionIDs.count == portions.count ? "Deselect All" : "Select All") {
                        if selectedPortionIDs.count == portions.count {
                            selectedPortionIDs.removeAll()
                        } else {
                            selectedPortionIDs = Set(portions.map(\.id))
                        }
                        Haptics.tick()
                    }
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.accent)
                }

                VStack(spacing: OTSpace.s) {
                    ForEach(portions) { portion in
                        let isSelected = selectedPortionIDs.contains(portion.id)
                        let isForMyRole = portion.characters.contains { $0.caseInsensitiveCompare(roleText) == .orderedSame }
                        VStack(alignment: .leading, spacing: OTSpace.xs) {
                            Button {
                                if isSelected {
                                    selectedPortionIDs.remove(portion.id)
                                } else {
                                    selectedPortionIDs.insert(portion.id)
                                }
                                Haptics.tick()
                            } label: {
                                HStack(alignment: .top, spacing: OTSpace.s) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.otIcon(.m))
                                        .foregroundStyle(isSelected ? OT.accent : OT.labelTertiary)
                                        .padding(.top, OTSpace.xxs)

                                    VStack(alignment: .leading, spacing: OTSpace.xs) {
                                        Text(portion.pageNumber.map { "Page \($0)" } ?? "Scene \(portion.number)")
                                            .font(.otCaption)
                                            .foregroundStyle(OT.labelSecondary)
                                        Text(portion.displayTitle)
                                            .font(.otSubhead.weight(.semibold))
                                            .foregroundStyle(OT.labelPrimary)
                                        if isForMyRole {
                                            Text("Matches your role")
                                                .font(.otCaption.weight(.semibold))
                                                .foregroundStyle(OT.accent)
                                        }
                                        let excerpt = portion.rawText.split(whereSeparator: \.isNewline)
                                            .map { $0.trimmingCharacters(in: .whitespaces) }
                                            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(portion.heading) != .orderedSame }
                                            .joined(separator: " ")
                                        if !excerpt.isEmpty {
                                            Text(excerpt)
                                                .font(.otFootnote)
                                                .foregroundStyle(OT.labelSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding(OTSpace.m)
                                .background(isSelected ? OT.accentSoft.opacity(0.3) : OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)) // ot-lint:allow
                                .overlay(
                                    RoundedRectangle(cornerRadius: OTRadius.m, style: .continuous)
                                        .stroke(isSelected ? OT.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            Button("Preview text") { preview = portion }
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.accent)
                                .accessibilityLabel("Preview \(portion.displayTitle)")
                                .padding(.horizontal, OTSpace.m)
                                .padding(.bottom, OTSpace.s)
                        }
                    }
                }
                .otCard(.grouped)

                // Reader audio option if lines for reader are present
                if hasReaderLines {
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        HStack {
                            Label("Practice cue audio", systemImage: "waveform")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Spacer()
                            HStack(spacing: OTSpace.xs) {
                                Text("Other character").font(.otCaption.weight(.bold)).foregroundStyle(OT.reader)
                                Text(detectedReaderName).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.reader)
                            }
                        }
                        Text("Record the other character’s lines in your voice. They’ll play back as cues while you perform.")
                            .font(.otFootnote).foregroundStyle(OT.labelSecondary)

                        Picker("Reader audio", selection: $readerAudioPlan) {
                            Text("Record now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                            Text("Later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                        }
                        .pickerStyle(.segmented)
                    }
                    .otCard(.grouped)
                }
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.m)
            .padding(.bottom, OTSpace.xl)
        }
        .sheet(item: $preview) { portion in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: OTSpace.m) {
                        Text(portion.displayTitle)
                            .font(.otTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(portion.rawText)
                            .font(.otBody)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OTSpace.gutter)
                }
                .navigationTitle("Text preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { preview = nil }
                    }
                }
            }
        }
    }
}
