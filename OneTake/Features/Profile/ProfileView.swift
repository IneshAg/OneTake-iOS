import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var showSignIn = false
    @State private var showGestureSettings = false
    @State private var showResumePicker = false
    @State private var resumeImportError: String?
    @AppStorage("camera.gesturesEnabled") private var showGestures = false
    @AppStorage("slateAtStart") private var slateAtStart = true
    @AppStorage("readerVolume") private var readerVolume = "Quieter"
    @AppStorage("practice.showSample") private var showSampleScene = true
    @AppStorage(AppStore.demoEnabledKey) private var demoModeEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                // Slate & Headshot Card
                slateAndHeadshotCard

                // Recording Section
                recordingSection

                // Demo & Testing Section
                demoSection

                // More Section
                moreSection

                // Account Section
                accountSection
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.showProfile {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.showProfile = false }
                }
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .fileImporter(isPresented: $showResumePicker, allowedContentTypes: [
            .pdf, .rtf, .plainText,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data
        ]) { result in
            switch result {
            case .success(let url):
                do {
                    store.slate.resumeURL = try ResumeStore.importFile(from: url)
                    Haptics.success()
                } catch {
                    resumeImportError = "Choose a PDF, Word document, RTF, or plain text résumé."
                }
            case .failure(let error):
                resumeImportError = error.localizedDescription
            }
        }
        .alert("Couldn't add résumé", isPresented: Binding(
            get: { resumeImportError != nil },
            set: { if !$0 { resumeImportError = nil } }
        )) {
            Button("OK", role: .cancel) { resumeImportError = nil }
        } message: {
            Text(resumeImportError ?? "Try choosing a résumé file again.")
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { account in store.account = account; showSignIn = false }
        }
        .sheet(isPresented: $showGestureSettings) {
            HandsFreeGestureSettingsView()
        }
    }

    private var slateAndHeadshotCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.push(.editSlate) } label: {
                HStack(spacing: OTSpace.m) {
                    HeadshotImage(realKey: "front", iconSize: 28).id(store.headshotVersion)
                        .frame(width: 52, height: 52) // ot-lint:allow
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                        Text(store.slate.name.isEmpty ? "Add your name" : store.slate.name)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text(store.slate.summary)
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                }
                .padding(.vertical, OTSpace.s)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit slate")

            Divider()

            Button { store.push(.headshots(for: nil)) } label: {
                HStack {
                    Label("Headshots", systemImage: "person.crop.square")
                        .font(.otBody).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Text("\(HeadshotStore.taken.count) of 3")
                        .font(.otCallout).foregroundStyle(OT.labelTertiary).id(store.headshotVersion)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                }
                .frame(minHeight: 44) // ot-lint:allow
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: OTSpace.s) {
                Label("Résumé", systemImage: "doc.text")
                    .font(.otBody).foregroundStyle(OT.labelPrimary)
                Spacer(minLength: OTSpace.s)
                if let resumeURL = store.slate.resumeURL {
                    Text(resumeURL.lastPathComponent)
                        .font(.otCaption).foregroundStyle(OT.labelSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Replace") { showResumePicker = true }
                        .font(.otCaption.weight(.semibold)).foregroundStyle(OT.accent)
                } else {
                    Button("Add PDF") { showResumePicker = true }
                        .buttonStyle(.ot(.secondary, size: .small, fullWidth: false))
                }
            }
            .frame(minHeight: 44) // ot-lint:allow
            .accessibilityElement(children: .contain)
        }
        .profileSectionCard()
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            OTSectionLabel("Recording")

            VStack(spacing: 0) {
                Toggle(isOn: $slateAtStart) {
                    Text("Slate at the start").font(.otBody).foregroundStyle(OT.labelPrimary)
                }
                .tint(OT.accent)
                .frame(minHeight: 44) // ot-lint:allow

                Divider()

                HStack {
                    Text("Reader volume").font(.otBody).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Picker("Reader volume", selection: $readerVolume) {
                        ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) }
                    }
                    .tint(OT.accent)
                }
                .frame(minHeight: 44) // ot-lint:allow
            }
            .profileSectionCard()
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            OTSectionLabel("Demo & Testing")

            VStack(spacing: 0) {
                Toggle(isOn: $demoModeEnabled) {
                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                        Text("Demo mode").font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                        Text("Sample auditions, playable takes, reader cues & practice drills")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }
                }
                .tint(OT.accent)
                .padding(.vertical, OTSpace.xxs)
                .frame(minHeight: 44) // ot-lint:allow
                .onChange(of: demoModeEnabled) { _, enabled in
                    if enabled {
                        store.enableDemoMode()
                        Haptics.success()
                    } else {
                        store.disableDemoMode()
                        Haptics.tick()
                    }
                }

                if demoModeEnabled {
                    Divider()

                    HStack(spacing: OTSpace.xs) {
                        if store.isPreparingDemoMedia {
                            ProgressView()
                            Text("Preparing playable demo clips…")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.otFootnote)
                                .foregroundStyle(OT.accent)
                            Text("\(store.demoAuditionCount) auditions · \(store.demoTakeCount) takes · \(store.demoPracticeCount) practice scenes")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, OTSpace.xs)

                    Divider()

                    Button { store.openDemoReadyAudition(); Haptics.tick() } label: {
                        profileRow(symbol: "play.rectangle", title: "Open ready tape (Midnight Dispatch)")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button { store.launchDemoNoticeReview(); Haptics.tick() } label: {
                        profileRow(symbol: "doc.text.magnifyingglass", title: "Test Notice Review flow")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button { store.resetDemoData(); Haptics.success() } label: {
                        HStack {
                            Label("Reset demo data", systemImage: "arrow.counterclockwise")
                                .font(.otBody).foregroundStyle(OT.accent)
                            Spacer()
                        }
                        .frame(minHeight: 44) // ot-lint:allow
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Toggle(isOn: $showSampleScene) {
                    Text("Show sample scene when empty")
                        .font(.otBody).foregroundStyle(OT.labelPrimary)
                }
                .tint(OT.accent)
                .frame(minHeight: 44) // ot-lint:allow
                .onChange(of: showSampleScene) { _, enabled in
                    if !enabled { store.removeSampleData(); Haptics.tick() }
                }
            }
            .profileSectionCard()
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            OTSectionLabel("More")

            VStack(spacing: 0) {
                HStack {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(.otBody).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .labelsHidden()
                }
                .frame(minHeight: 44) // ot-lint:allow

                Divider()

                Button { showGestureSettings = true } label: {
                    HStack {
                        Label("Hands-free controls", systemImage: "hand.raised")
                            .font(.otBody).foregroundStyle(OT.labelPrimary)
                        Spacer()
                        Text(showGestures ? "On" : "Off")
                            .font(.otCallout).foregroundStyle(OT.labelTertiary)
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                    }
                    .frame(minHeight: 44) // ot-lint:allow
                }
                .buttonStyle(.plain)

                Divider()

                Button { store.push(.notifications) } label: {
                    profileRow(symbol: "bell", title: "Notifications")
                }
                .buttonStyle(.plain)

                Divider()

                Button { store.push(.privacy) } label: {
                    profileRow(symbol: "hand.raised", title: "Privacy & data")
                }
                .buttonStyle(.plain)
            }
            .profileSectionCard()
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            OTSectionLabel("Account")

            VStack(spacing: 0) {
                if let account = store.account {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                Text(account.name ?? account.email ?? "Signed in")
                                    .font(.otBody.weight(.medium))
                                    .foregroundStyle(OT.labelPrimary)
                                Text("With \(account.providerName)" + (account.name != nil ? (account.email.map { " · \($0)" } ?? "") : ""))
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelTertiary)
                            }
                        } icon: { Image(systemName: "person").foregroundStyle(OT.accent) }
                        Spacer()
                    }
                    .frame(minHeight: 44) // ot-lint:allow

                    Divider()

                    Button { store.signOut(); Haptics.tick() } label: {
                        HStack {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.otBody.weight(.medium))
                                .foregroundStyle(OT.danger)
                            Spacer()
                        }
                        .frame(minHeight: 44) // ot-lint:allow
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showSignIn = true } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                Label("Sign in", systemImage: "person.badge.plus")
                                    .font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                Text("Needed only to send an iCloud link.")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44) // ot-lint:allow
                    }
                    .buttonStyle(.plain)
                }
            }
            .profileSectionCard()
        }
    }

    private func profileRow(symbol: String, title: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.otBody).foregroundStyle(OT.labelPrimary)
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: 44) // ot-lint:allow
    }
}

private struct HandsFreeGestureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("camera.gesturesEnabled") private var enabled = false
    @AppStorage("camera.voiceCommandsEnabled") private var voiceCommandsEnabled = true
    @AppStorage("camera.gestureHoldDuration") private var holdDuration = 1.2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Voice commands (Action / Cut)", isOn: $voiceCommandsEnabled)
                    Toggle("Hand gestures (open palm)", isOn: $enabled)
                    Picker("Hold gesture for", selection: $holdDuration) {
                        Text("0.8 seconds").tag(0.8)
                        Text("1.2 seconds").tag(1.2)
                        Text("1.8 seconds").tag(1.8)
                    }
                    .disabled(!enabled)
                } footer: {
                    Text("Choose voice commands, gestures, or both. Hold an open palm toward the camera to start, pause, or resume. Starting uses the camera countdown when it’s on; tap Record to finish a take.")
                }
            }
            .scrollContentBackground(.hidden)
            .otCanvas()
            .navigationTitle("Hands-free controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private extension View {
    /// Matches native iOS settings card proportion: standard side inset with snug vertical padding.
    func profileSectionCard() -> some View {
        self
            .padding(.horizontal, OTSpace.cardInset)
            .padding(.vertical, OTSpace.xs)
            .otCard(.grouped, padding: nil)
    }
}
