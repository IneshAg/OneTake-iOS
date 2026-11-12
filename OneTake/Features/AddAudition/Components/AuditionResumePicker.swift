import SwiftUI
import UniformTypeIdentifiers
import OneTakeUI

struct AuditionResumePicker: View {
    @Environment(AppStore.self) private var store
    @Binding var isIncluded: Bool
    @Binding var selectedURL: URL?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    private var resumeURL: URL? { selectedURL ?? store.slate.resumeURL }
    private var includeBinding: Binding<Bool> {
        Binding(
            get: { isIncluded },
            set: { newValue in
                isIncluded = newValue
                if newValue, selectedURL == nil { selectedURL = store.slate.resumeURL }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            Label("Résumé", systemImage: "doc.text")
                .font(.otFootnote.weight(.semibold))
                .foregroundStyle(OT.labelPrimary)

            if let resumeURL {
                Toggle(isIncluded ? "Include with this audition" : "Don't include with this audition", isOn: includeBinding)
                    .font(.otFootnote)
                    .tint(OT.accent)
                Text(resumeURL.lastPathComponent)
                    .font(.otCaption).foregroundStyle(OT.labelSecondary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text("No résumé saved to your profile yet.")
                    .font(.otFootnote).foregroundStyle(OT.labelSecondary)
            }

            Button(resumeURL == nil ? "Add résumé to Profile" : "Replace profile résumé") {
                showingImporter = true
            }
            .font(.otFootnote.weight(.semibold))
            .foregroundStyle(OT.accent)

            Text("Your profile résumé is reusable. Choose whether to include it for this audition.")
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .otCard(.grouped)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [
            .pdf, .rtf, .plainText,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data
        ]) { result in
            switch result {
            case .success(let url):
                do {
                    let savedURL = try ResumeStore.importFile(from: url)
                    store.slate.resumeURL = savedURL
                    selectedURL = savedURL
                    isIncluded = true
                    Haptics.success()
                } catch {
                    errorMessage = "Choose a PDF, Word, RTF, or plain text résumé."
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't add résumé", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try choosing a résumé file again.")
        }
    }
}
