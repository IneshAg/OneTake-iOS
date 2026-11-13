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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                // Header
                VStack(alignment: .leading, spacing: OTSpace.xs) {
                    Label("Scenes & Pages to prepare", systemImage: "doc.text")
                        .font(.otTitle)
                    Text("Choose the relevant \(portionsArePages ? "pages" : "scenes") for \(roleText.isEmpty ? "your role" : roleText).")
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
                                    HStack {
                                        Text(portion.displayTitle)
                                            .font(.otSubhead.weight(.semibold))
                                            .foregroundStyle(OT.labelPrimary)
                                        Spacer()
                                        if isForMyRole {
                                            Text("Matches role")
                                                .font(.otCaption.weight(.bold))
                                                .padding(.horizontal, OTSpace.xs)
                                                .padding(.vertical, OTSpace.xxs)
                                                .background(OT.accentSoft, in: Capsule())
                                                .foregroundStyle(OT.accent)
                                        }
                                    }

                                    if !portion.characters.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: OTSpace.xs) {
                                                ForEach(portion.characters.prefix(4), id: \.self) { c in
                                                    Text(c)
                                                        .font(.otCaption.weight(.medium))
                                                        .padding(.horizontal, OTSpace.xs)
                                                        .padding(.vertical, OTSpace.xxs)
                                                        .background(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accentSoft : OT.fillField, in: RoundedRectangle(cornerRadius: OTRadius.xs))
                                                        .foregroundStyle(c.caseInsensitiveCompare(roleText) == .orderedSame ? OT.accent : OT.labelSecondary)
                                                }
                                            }
                                        }
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
    }
}
