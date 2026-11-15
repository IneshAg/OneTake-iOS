import SwiftUI
import OneTakeUI

/// Dedicated full-height script text editing screen so editing sides never gets cramped under
/// action buttons or the software keyboard.
struct ScriptTextEditSheet: View {
    var title: String = "Edit script"
    var subtitle: String = "Put character cues in CAPS (e.g. MAYA) or \"Maya: line\"."
    var roleName: String = ""
    @State private var draftText: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String = "Edit script",
        subtitle: String = "Put character cues in CAPS (e.g. MAYA) or \"Maya: line\".",
        roleName: String = "",
        initialText: String,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.roleName = roleName
        _draftText = State(initialValue: initialText)
        self.onSave = onSave
    }

    private var previewScenes: [ScriptScene] {
        ScriptParser.parseScenes(from: draftText, myRole: roleName)
    }

    private var parsedLinesCount: Int {
        previewScenes.flatMap(\.lines).count
    }

    private var myLinesCount: Int {
        previewScenes.flatMap(\.lines).filter(\.isMine).count
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                HStack(spacing: OTSpace.s) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(OT.accent)
                    Text(subtitle)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                    Spacer()
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.xs)

                ScriptTextEditor(text: $draftText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .otCard(.grouped, padding: OTSpace.xs)
                    .padding(.horizontal, OTSpace.gutter)

                HStack(spacing: OTSpace.s) {
                    OTChip("\(parsedLinesCount) lines parsed", tint: OT.accent)
                    if !roleName.isEmpty {
                        OTChip("\(myLinesCount) for \(roleName)", tint: OT.success)
                    }
                    Spacer()
                    Button("Paste") {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            draftText = ScriptParser.cleanPastedText(clip)
                            Haptics.tick()
                        }
                    }
                    .buttonStyle(.otCompact)

                    if !draftText.isEmpty {
                        Button("Clear") {
                            draftText = ""
                            Haptics.tick()
                        }
                        .buttonStyle(.otCompact)
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.bottom, OTSpace.s)
            }
            .otCanvas()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftText)
                        Haptics.success()
                        dismiss()
                    }
                    .font(.otHeadline)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
