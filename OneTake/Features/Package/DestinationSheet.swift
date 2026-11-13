import SwiftUI

struct DestinationSheet: View {
    let auditionID: Audition.ID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            Group {
                if let audition = store.binding(for: auditionID) {
                    let current = audition.wrappedValue.destination
                    let wasChosen = audition.wrappedValue.destinationWasChosen ?? false
                    List {
                    Section("Destination & Submission Method") {
                        ForEach(Destination.allCases) { d in
                            destinationRow(for: d, isSelected: wasChosen && current == d) {
                                if current != d { store.clearShareLink(for: auditionID) }
                                audition.wrappedValue.destination = d
                                audition.wrappedValue.destinationWasChosen = true
                                Haptics.tick()
                            }
                        }
                    }

                    if store.account == nil {
                        Section("Account") {
                            Button { showSignIn = true } label: {
                                Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus")
                            }
                            Text(AccountAuth.canSignIn
                                 ? "Sign in here to use a hosted link. You’ll return to this audition afterward."
                                 : "The sign-in screen is available here, but Apple and Google aren’t configured in this build yet.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                    }

                    if wasChosen {
                        Section {
                            TextField(
                                current == .email ? "Casting email address (e.g. casting@production.com)" :
                                current == .emailOrLink ? "Hosted link (Google Drive / YouTube / Vimeo / iCloud)" :
                                "\(current.rawValue) account or submission notes",
                                text: destinationDetailBinding(for: audition)
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(current == .email ? .emailAddress : .default)
                        } header: {
                            Text(current == .email ? "Casting Recipient Email" : "Details & Notes")
                        } footer: {
                            VStack(alignment: .leading, spacing: OTSpace.xs) {
                                Text(current == .email ? "We automatically format the cover email, subject line, and attach your chosen deliverable." :
                                     current == .localFiles ? "Export directly to your iPhone Files app, AirDrop to your computer, or copy to cloud storage." :
                                     "We match the file name and specifications each platform asks for.")
                                if !AccountAuth.canSignIn {
                                    Text("Sign-in options are in Profile → Sign in. Apple and Google sign-in are not configured in this build, so hosted links are unavailable.")
                                }
                            }
                        }
                    } else {
                        Section {
                            VStack(alignment: .leading, spacing: OTSpace.xs) {
                                Text("Choose the place you’ll send your audition. The notice’s email has been preselected when detected.")
                                if !AccountAuth.canSignIn {
                                    Text("Sign-in options are in Profile → Sign in. Apple and Google sign-in are not configured in this build, so hosted links are unavailable.")
                                }
                            }
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                        }
                    }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .otCanvas()
            .navigationTitle("Where’s it going?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(reason: "Sign in here to use a hosted link. You’ll return to this audition afterward.") { account in
                store.account = account
                showSignIn = false
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func destinationRow(for d: Destination, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(spacing: OTSpace.m) {
                Image(systemName: d.icon)
                    .font(.system(size: 18, weight: .semibold)) // ot-lint:allow
                    .foregroundStyle(isSelected ? OT.accent : OT.labelSecondary)
                    .frame(width: 24) // ot-lint:allow

                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                    Text(d.rawValue).font(.otBody)
                    Text(d.spec).font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    if d == .emailOrLink {
                        Text(linkStatus.text).font(.otFootnote).foregroundStyle(linkStatus.color)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OT.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func destinationDetailBinding(for audition: Binding<Audition>) -> Binding<String> {
        Binding(
            get: {
                if let detail = audition.wrappedValue.destinationDetail, !detail.isEmpty {
                    return detail
                }
                if let email = audition.wrappedValue.castingEmail {
                    return email
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                audition.wrappedValue.destinationDetail = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var linkStatus: (text: String, color: Color) {
        if !AccountAuth.canSignIn {
            return ("Not available in this build — needs Apple or Google sign-in", OT.warning)
        }
        if !CloudLink.isAvailable {
            return ("Needs iCloud — sign in from Settings", OT.warning)
        }
        return ("Uploads to your iCloud Drive", OT.labelTertiary)
    }
}
