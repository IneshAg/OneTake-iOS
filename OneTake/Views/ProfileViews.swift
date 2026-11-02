import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

// MARK: - 10 Profile (tab)

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var showSignIn = false
    @State private var showGestureSettings = false
    @AppStorage("camera.gesturesEnabled") private var showGestures = false
    @AppStorage("slateAtStart") private var slateAtStart = true
    @AppStorage("readerVolume") private var readerVolume = "Quieter"
    @AppStorage("practice.showSample") private var showSampleScene = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(alignment: .center) {
                    Text("Profile").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Button("Done") {
                        store.showProfile = false
                    }
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(OT.fillField, in: Capsule())
                }
                .padding(.top, 30)

                // Slate & Headshot Card
                VStack(alignment: .leading, spacing: 14) {
                    Button { store.push(.editSlate) } label: {
                        HStack(spacing: 14) {
                            HeadshotImage(realKey: "front", iconSize: 28).id(store.headshotVersion)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.slate.name.isEmpty ? "Add your name" : store.slate.name).font(.otTitle).foregroundStyle(OT.labelPrimary)
                                Text(store.slate.summary)
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(OT.accent).frame(width: 36, height: 36).background(OT.accentSoft, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit slate")

                    Divider()

                    Button { store.push(.headshots(for: nil)) } label: {
                        HStack {
                            Label("Headshots", systemImage: "person.crop.square")
                                .font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Text("\(HeadshotStore.taken.count) of 3").font(.otCallout).foregroundStyle(OT.labelTertiary).id(store.headshotVersion)
                            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .otCard(radius: 20)

                // Every time you record
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Recording")

                    VStack(spacing: 0) {
                        // "Room noise" and "Export" settings used to sit here; nothing ever applied
                        // them, so they're gone until there's processing behind them.
                        Toggle(isOn: $slateAtStart) {
                            Text("Slate at the start").font(.otBody).foregroundStyle(OT.labelPrimary)
                        }
                            .tint(OT.accent)
                            .frame(minHeight: 48)

                        Divider().padding(.vertical, 4)

                        HStack {
                            Text("Reader volume").font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Picker("Reader volume", selection: $readerVolume) {
                                ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) }
                            }
                            .tint(OT.accent)
                        }
                        .frame(minHeight: 48)

                    }
                    .padding(18)
                    .otCard(radius: 20)
                }

                // Practice sample
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Practice")

                    Toggle(isOn: $showSampleScene) {
                        Text("Show sample scene").font(.otBody).foregroundStyle(OT.labelPrimary)
                    }
                    .tint(OT.accent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 60)
                    .otCard(radius: 20)
                }

                // More section
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "More")

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
                        .frame(minHeight: 44)

                        Divider().padding(.vertical, 2)

                        Button { showGestureSettings = true } label: {
                            HStack {
                                Label("Hands-free gestures", systemImage: "hand.raised")
                                    .font(.otBody).foregroundStyle(OT.labelPrimary)
                                Spacer()
                                Text(showGestures ? "On" : "Off")
                                    .font(.otCallout).foregroundStyle(OT.labelTertiary)
                                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 2)

                        Button { store.push(.notifications) } label: {
                            profileRow(symbol: "bell", title: "Notifications")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 2)

                        Button { store.push(.privacy) } label: {
                            profileRow(symbol: "hand.raised", title: "Privacy & data")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .otCard(radius: 20)
                }

                // Account section (moved down)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Account")

                    VStack(spacing: 0) {
                        if let account = store.account {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name ?? account.email ?? "Signed in").font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                        Text("With \(account.providerName)" + (account.name != nil ? (account.email.map { " · \($0)" } ?? "") : ""))
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                } icon: { Image(systemName: "person.crop.circle.fill").foregroundStyle(OT.accent) }
                                Spacer()
                            }
                            .frame(minHeight: 44)

                            Divider().padding(.vertical, 2)

                            // Signs out only — onboarding, auditions and takes stay exactly as they are.
                            Button { store.signOut(); Haptics.tick() } label: {
                                HStack {
                                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.otBody.weight(.medium))
                                        .foregroundStyle(OT.danger)
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button { showSignIn = true } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                                            .font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                        Text("Needed only to send an iCloud link.")
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .otCard(radius: 20)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 120)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(isPresented: $showSignIn) {
            SignInView { account in store.account = account; showSignIn = false }
        }
        .sheet(isPresented: $showGestureSettings) {
            HandsFreeGestureSettingsView()
        }
    }

    private func profileRow(symbol: String, title: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.otBody).foregroundStyle(OT.labelPrimary)
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: 44)
    }
}

private struct HandsFreeGestureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("camera.gesturesEnabled") private var enabled = false
    @AppStorage("camera.gestureHoldDuration") private var holdDuration = 1.2

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Hands-free gestures", backLabel: "Done", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)

            Form {
                Section {
                    Toggle("Use hand gestures", isOn: $enabled)
                    Picker("Hold gesture for", selection: $holdDuration) {
                        Text("0.8 seconds").tag(0.8)
                        Text("1.2 seconds").tag(1.2)
                        Text("1.8 seconds").tag(1.8)
                    }
                    .disabled(!enabled)
                } footer: {
                    Text("Hold an open palm toward the camera to start, pause, or resume. Starting uses the camera countdown when it’s on. Tap Record to finish a take.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 10.1 Edit slate

struct EditSlateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var draft = SlateInfo()
    @State private var heightUnit = HeightUnit.feetInches
    @State private var feet = ""
    @State private var inches = ""
    @State private var centimetres = ""

    private enum Field { case name, height, basedIn, representation }
    private enum HeightUnit: String, Hashable { case feetInches = "ft / in", centimetres = "cm" }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Edit slate", backLabel: "Back", onBack: { store.pop() }) {
                Button("Save") {
                    focusedField = nil
                    store.slate = draft
                    store.pop()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 4)

            Form {
            Section("Your slate") {
                slateField("Name", placeholder: "e.g. Maya Sharma", text: $draft.name, field: .name,
                           contentType: .name, capitalization: .words, next: .height)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height").font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)
                    Picker("Height unit", selection: Binding(get: { heightUnit }, set: changeHeightUnit)) {
                        Text("ft / in").tag(HeightUnit.feetInches)
                        Text("cm").tag(HeightUnit.centimetres)
                    }
                    .pickerStyle(.segmented)

                    if heightUnit == .feetInches {
                        HStack(spacing: 10) {
                            TextField("Feet", text: $feet)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .height)
                                .onChange(of: feet) { oldValue, newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(1))
                                    if let number = Int(digits), number > 8 { feet = oldValue; return }
                                    if digits != newValue { feet = digits; updateHeight(); return }
                                    updateHeight()
                                }
                            Text("ft").foregroundStyle(OT.labelTertiary)
                            TextField("Inches", text: $inches)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .height)
                                .onChange(of: inches) { oldValue, newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(2))
                                    if let number = Int(digits), number > 11 { inches = oldValue; return }
                                    if digits != newValue { inches = digits; updateHeight(); return }
                                    updateHeight()
                                }
                            Text("in").foregroundStyle(OT.labelTertiary)
                        }
                    } else {
                        HStack(spacing: 10) {
                            TextField("Centimetres", text: $centimetres)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .height)
                                .onChange(of: centimetres) { oldValue, newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(3))
                                    if let number = Int(digits), number > 250 { centimetres = oldValue; return }
                                    if digits != newValue { centimetres = digits; updateHeight(); return }
                                    updateHeight()
                                }
                            Text("cm").foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
                .padding(.vertical, 4)
                slateField("Based in", placeholder: "e.g. London", text: $draft.basedIn, field: .basedIn,
                           capitalization: .words, next: .representation)
                slateField("Representation", placeholder: "Agency or self-represented", text: $draft.representation,
                           field: .representation, capitalization: .words, next: nil)
            }
            Section("Preview") {
                Text(draft.spoken.isEmpty ? "Your slate preview will appear here." : draft.spoken)
                    .font(.otHeadline)
                    .foregroundStyle(draft.spoken.isEmpty ? OT.labelTertiary : OT.labelPrimary)
            }
            .scrollContentBackground(.hidden)
        }
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear(perform: loadDraft)
    }

    private func slateField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType? = nil,
        capitalization: TextInputAutocapitalization,
        next: Field?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)
            TextField(placeholder, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .focused($focusedField, equals: field)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { focusedField = next }
        }
        .padding(.vertical, 4)
    }

    private func loadDraft() {
        draft = store.slate
        let digits = String(draft.height.filter(\.isNumber))
        let hasImperialUnit = draft.height.contains("′") || draft.height.contains("″")
            || draft.height.localizedCaseInsensitiveContains("ft")
            || draft.height.localizedCaseInsensitiveContains("in")
        let isUnlabeledMetric = !hasImperialUnit && digits.count == 3 && (Int(digits) ?? 0) <= 250
        if draft.height.localizedCaseInsensitiveContains("cm") || isUnlabeledMetric {
            heightUnit = .centimetres
            centimetres = String(digits.prefix(3))
        } else {
            heightUnit = .feetInches
            feet = String(digits.prefix(1))
            inches = String(digits.dropFirst().prefix(2))
        }
    }

    private func changeHeightUnit(to newUnit: HeightUnit) {
        guard heightUnit != newUnit else { return }
        if newUnit == .centimetres {
            let totalInches = (Int(feet) ?? 0) * 12 + (Int(inches) ?? 0)
            centimetres = totalInches == 0 ? "" : String(Int((Double(totalInches) * 2.54).rounded()))
        } else {
            let totalInches = Int((Double(Int(centimetres) ?? 0) / 2.54).rounded())
            feet = totalInches == 0 ? "" : String(totalInches / 12)
            inches = totalInches == 0 ? "" : String(totalInches % 12)
        }
        heightUnit = newUnit
        updateHeight()
    }

    private func updateHeight() {
        switch heightUnit {
        case .feetInches:
            let parts = [feet.isEmpty ? nil : "\(feet)′", inches.isEmpty ? nil : "\(inches)″"].compactMap { $0 }
            draft.height = parts.joined(separator: " ")
        case .centimetres:
            draft.height = centimetres.isEmpty ? "" : "\(centimetres) cm"
        }
    }
}

// MARK: - 10b Privacy & data

struct PrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var showConfirmDeleteAll = false
    @State private var showConfirmDisconnectAccount = false
    @State private var showConfirmClearExports = false
    @State private var showConfirmClearReader = false
    @State private var storageRefreshID = UUID()
    @State private var showBackupImporter = false
    @State private var showBackupShare = false
    @State private var showRestoreConfirmation = false
    @State private var showBackupError = false
    @State private var backupErrorMessage = ""
    @State private var isWorkingWithBackup = false
    @State private var backupArchiveURL: URL?
    @State private var pendingBackup: PendingBackup?

    private struct PendingBackup {
        let directory: URL
        let payload: LocalBackupPayload
    }

    private var rawTakesSize: Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path) else { return 0 }
        let takeFolders = entries.filter { ($0.hasPrefix("audition-") || $0.hasPrefix("practice-") || $0 == "takes") && $0 != "Exports" }
        return takeFolders.reduce(Int64(0)) { $0 + MediaStore.sizeOnDisk($1) }
    }
    private var exportsSize: Int64 { MediaStore.sizeOnDisk("Exports") }
    private var headshotsSize: Int64 { MediaStore.sizeOnDisk("headshots") }
    private var readerSize: Int64 { MediaStore.sizeOnDisk(ReaderTrackPlayer.folder) + legacyReaderFiles.reduce(Int64(0)) { total, url in
        total + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
    } }
    /// Reader lines from before tracks were scoped per audition lived loose in Documents as
    /// `reader-line-N.m4a`; still counted and deleted so they don't linger invisibly.
    private var legacyReaderFiles: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path)) ?? []
        return entries.filter { $0.hasPrefix("reader-line-") }.map { MediaStore.documentsURL.appendingPathComponent($0) }
    }
    private var totalSize: Int64 { rawTakesSize + exportsSize + headshotsSize + readerSize }

    private func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Privacy & data", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            List {
                overviewSection
                transferSection
                cloudSection
                localStorageSection
                accountSection
                legalSection
            }
        .id(storageRefreshID)
        .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.zip]) { result in
            importBackup(result)
        }
        .sheet(isPresented: $showBackupShare, onDismiss: {
            LocalBackup.discardArchive(backupArchiveURL)
            backupArchiveURL = nil
        }) {
            if let backupArchiveURL {
                ShareSheet(items: [backupArchiveURL]) { _ in showBackupShare = false }
            }
        }
        .confirmationDialog("Replace local data with this backup?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Replace local data", role: .destructive) { restoreBackup() }
            Button("Cancel", role: .cancel) { discardPendingBackup() }
        } message: {
            Text("This replaces auditions, recordings, headshots, practice and settings on this iPhone.")
        }
        .alert("Backup could not be used", isPresented: $showBackupError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupErrorMessage)
        }
        .confirmationDialog("Clear exported deliverables?", isPresented: $showConfirmClearExports, titleVisibility: .visible) {
            Button("Clear deliverables cache", role: .destructive) {
                clearExports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Original takes stay on this iPhone.")
        }
        .confirmationDialog("Clear reader audio?", isPresented: $showConfirmClearReader, titleVisibility: .visible) {
            Button("Clear reader recordings", role: .destructive) {
                clearReader()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scripts and scenes stay on this iPhone.")
        }
        .confirmationDialog("Disconnect account?", isPresented: $showConfirmDisconnectAccount, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                store.deleteAccount()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete all local data?", isPresented: $showConfirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(OT.accent)
                        .font(.title3)
                    Text("100% OFFLINE & PRIVATE")
                        .font(.otEyebrow)
                        .foregroundStyle(OT.labelTertiary)
                    Spacer()
                    Text(mb(totalSize))
                        .font(.otHeadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var transferSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export backup", systemImage: "square.and.arrow.up")
            }
            .disabled(isWorkingWithBackup)

            Button {
                showBackupImporter = true
            } label: {
                Label("Import backup", systemImage: "square.and.arrow.down")
            }
            .disabled(isWorkingWithBackup)

            if isWorkingWithBackup {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Working with backup…").font(.otFootnote).foregroundStyle(OT.labelSecondary)
                }
            }
        } header: {
            Text("Transfer data")
        } footer: {
            Text("Backups include auditions, recordings, headshots, practice and settings. They stay in Files until you choose to share them.")
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        Section {
            LabeledContent("iCloud Drive", value: CloudLink.isAvailable ? "Available" : "Not connected")
            if let account = store.account {
                LabeledContent("Sign-in Provider", value: account.providerName)
            }
        } header: {
            Text("Cloud Delivery")
        }
    }

    @ViewBuilder
    private var localStorageSection: some View {
        Section {
            LabeledContent("Takes & auditions", value: mb(rawTakesSize))
            LabeledContent("Headshots", value: mb(headshotsSize))
            LabeledContent("Reader tracks", value: mb(readerSize))
            LabeledContent("Exported deliverables", value: mb(exportsSize))

            if exportsSize > 0 {
                Button("Clear exported deliverables cache") {
                    showConfirmClearExports = true
                }
                .foregroundStyle(OT.accent)
            }
            if readerSize > 0 {
                Button("Clear practice reader audio") {
                    showConfirmClearReader = true
                }
                .foregroundStyle(OT.accent)
            }
        } header: {
            Text("On this iPhone")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let account = store.account {
                LabeledContent("Connected as", value: account.name ?? account.email ?? "Signed in")
                Button("Disconnect account", role: .destructive) {
                    showConfirmDisconnectAccount = true
                }
            } else {
                LabeledContent("Account mode", value: "Guest (No account)")
            }
        } header: {
            Text("Account")
        } footer: {
            Text(store.isSignedIn
                 ? "Disconnects sign-in on this iPhone."
                 : "Sign in only to send an iCloud link.")
        }
    }

    @ViewBuilder
    private var legalSection: some View {
        Section {
            NavigationLink("Privacy policy") { PrivacyPolicyView() }
            Button("Delete all local data", role: .destructive) { showConfirmDeleteAll = true }
        } footer: {
            Text("Sent tapes are not affected.")
        }
    }

    private func clearExports() {
        MediaStore.deleteAll(["Exports"])
        for i in store.auditions.indices {
            store.auditions[i].exportedFileURL = nil
        }
        storageRefreshID = UUID()
        Haptics.success()
    }

    private func clearReader() {
        MediaStore.deleteAll([ReaderTrackPlayer.folder])
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        store.readerTracksDidChange()
        storageRefreshID = UUID()
        Haptics.success()
    }

    private func exportBackup() {
        guard !isWorkingWithBackup else { return }
        isWorkingWithBackup = true
        do {
            let job = try LocalBackup.prepareExport(from: store)
            Task {
                do {
                    backupArchiveURL = try await Task.detached(priority: .userInitiated) {
                        try LocalBackup.writeArchive(job)
                    }.value
                    showBackupShare = true
                } catch {
                    backupErrorMessage = error.localizedDescription
                    showBackupError = true
                }
                isWorkingWithBackup = false
            }
        } catch {
            isWorkingWithBackup = false
            backupErrorMessage = error.localizedDescription
            showBackupError = true
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        guard !isWorkingWithBackup else { return }
        switch result {
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            isWorkingWithBackup = true
            Task {
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let directory = try await Task.detached(priority: .userInitiated) {
                        try LocalBackup.extract(from: url)
                    }.value
                    do {
                        let payload = try LocalBackup.readPayload(in: directory)
                        pendingBackup = PendingBackup(directory: directory, payload: payload)
                        showRestoreConfirmation = true
                    } catch {
                        LocalBackup.discardStaging(directory)
                        throw error
                    }
                } catch {
                    backupErrorMessage = error.localizedDescription
                    showBackupError = true
                }
                isWorkingWithBackup = false
            }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            backupErrorMessage = error.localizedDescription
            showBackupError = true
        }
    }

    private func restoreBackup() {
        guard let pendingBackup, !isWorkingWithBackup else { return }
        isWorkingWithBackup = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LocalBackup.replaceDocuments(with: pendingBackup.directory)
                }.value
                pendingBackup.payload.settings.apply()
                store.restoreLocalBackup(pendingBackup.payload.state)
                storageRefreshID = UUID()
                LocalBackup.discardStaging(pendingBackup.directory)
                self.pendingBackup = nil
                Haptics.success()
            } catch {
                backupErrorMessage = error.localizedDescription
                showBackupError = true
            }
            isWorkingWithBackup = false
        }
    }

    private func discardPendingBackup() {
        LocalBackup.discardStaging(pendingBackup?.directory)
        pendingBackup = nil
    }

    private func deleteAll() {
        MediaStore.deleteAll(["headshots", "takes", "Exports", ReaderTrackPlayer.folder] + store.auditions.map { "audition-\($0.id.uuidString)" } + store.practice.map { "practice-\($0.id.uuidString)" })
        HeadshotStore.clearCache()
        store.headshotVersion += 1
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        store.takes.removeAll()
        for i in store.auditions.indices {
            store.auditions[i].slateVideoURL = nil; store.auditions[i].slateOriginalVideoURL = nil; store.auditions[i].fullLengthVideoURL = nil; store.auditions[i].exportedFileURL = nil
            // The recordings and headshots behind these pieces are gone, so unsent auditions go back
            // to "not done" rather than claiming to be ready. Sent ones keep their history (and link).
            guard store.auditions[i].status != .sent else { continue }
            for j in store.auditions[i].pieces.indices { store.auditions[i].pieces[j].isDone = false }
            store.auditions[i].status = .due
        }
        for i in store.practice.indices { store.practice[i].takesRecorded = 0 }
        storageRefreshID = UUID()
        Haptics.success()
    }
}

// MARK: - Privacy policy

/// What OneTake does with your data, in the app itself — there's no website for it to point at.
/// Keep it in step with the code: every claim here should stay true.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InContentNavHeader(title: "Privacy policy", backLabel: "Back", onBack: { dismiss() })
                    .padding(.bottom, 6)

                section("Private by design", "OneTake has no ads, analytics or tracking. Your work stays on this iPhone unless you share it.")
                section("Signing in", "An account is optional. Sign in only to send a tape as an iCloud link.")
                section("On-device data", "Auditions, sides, takes, slate, headshots and practice are stored on this iPhone and included in its backups.")
                section("Reading sides", "Photos, scans and PDFs are read on-device with Apple Vision and PDFKit.")
                section("Speech recognition", "Voice commands use on-device recognition when available. Otherwise Apple may process speech under its privacy policy.")
                section("Sharing", "A tape leaves this iPhone only when you share it. iCloud links can be downloaded until they expire.")
                section("Reminders and widgets", "These use audition details stored on this iPhone.")
                section("Deleting data", "Delete local data in Profile → Privacy & data. Previously shared iCloud links remain in your iCloud Drive.")
            }
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 12)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
            Text(body).font(.otCallout).foregroundStyle(OT.labelSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 10c Notifications

struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("n.liveActivity") private var liveActivity = false
    @AppStorage("n.morning") private var morning = true
    @AppStorage("n.twoHours") private var twoHours = true
    @AppStorage("n.delivery") private var delivery = true
    @AppStorage("n.practice") private var practice = false

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testScheduled = false

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Notifications", backLabel: "Back", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            Form {
            if authStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications Disabled in Settings", systemImage: "bell.slash.fill")
                            .font(.otHeadline)
                            .foregroundStyle(OT.warning)
                        Text("Allow notifications in iOS Settings to receive reminders.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            } else if authStatus == .notDetermined {
                Section {
                    Button {
                        Task {
                            let granted = await Reminders.requestAuthorization()
                            await refreshStatus()
                            if granted { Reminders.reschedule(store.auditions) }
                        }
                    } label: {
                        HStack {
                            Label("Enable Deadline Reminders", systemImage: "bell.badge.fill")
                                .font(.otBody.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
            }

            Section {
                Toggle("Morning it’s due", isOn: $morning)
                Toggle("Two hours before", isOn: $twoHours)
                Toggle("Countdown on Lock Screen", isOn: $liveActivity)
            } header: {
                Text("Deadlines")
            }

            Section {
                Toggle("Link ready", isOn: $delivery)
                Toggle("Practice nudges · 6 pm", isOn: $practice)
            } header: {
                Text("Your tapes")
            } footer: {
                Text("Alerts you when an iCloud upload finishes.")
            }

            Section {
                Button {
                    Reminders.sendTestNotification()
                    testScheduled = true
                    Haptics.success()
                } label: {
                    HStack {
                        Label(testScheduled ? "Test Alert Scheduled (arrives in 3s)" : "Send Test Notification", systemImage: "bell.and.waveform")
                            .font(.otBody)
                        Spacer()
                    }
                }
            } footer: {
                Text("Sends a test alert in 3 seconds.")
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshStatus() }
            }
        }
        .onChange(of: morning) { checkAndReschedule() }
        .onChange(of: twoHours) { checkAndReschedule() }
        .onChange(of: practice) { checkAndReschedule() }
        .onChange(of: liveActivity) { LiveActivitySync.update(store.auditions) }
        .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func refreshStatus() async {
        let status = await Reminders.authorizationStatus()
        await MainActor.run { self.authStatus = status }
    }

    private func checkAndReschedule() {
        if authStatus == .notDetermined {
            Task {
                await Reminders.requestAuthorization()
                await refreshStatus()
                Reminders.reschedule(store.auditions)
            }
        } else {
            Reminders.reschedule(store.auditions)
        }
    }
}

// MARK: - 08 Headshots

struct HeadshotsView: View {
    /// Set when opened from an audition's checklist, so the screen can continue to its next step.
    var auditionID: Audition.ID? = nil
    @Environment(AppStore.self) private var store
    @State private var framingRatio: FramingRatio?
    @State private var adjustItem: HeadshotAdjustItem?
    @State private var isFraming = false

    /// Counted from the real files on disk for this specific audition or profile
    private var taken: Int {
        HeadshotStore.angles.prefix { HeadshotStore.exists(key: $0.key, auditionID: auditionID) }.count
    }

    private var profileTaken: Int {
        HeadshotStore.angles.prefix { HeadshotStore.exists(key: $0.key, auditionID: nil) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InContentNavHeader(
                    title: auditionID != nil ? "Audition Headshots" : "Default Headshots",
                    backLabel: "Back",
                    onBack: { store.pop() }
                )
                .padding(.top, 4)

                if let auditionID {
                    if taken > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(OT.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(taken) photo\(taken == 1 ? "" : "s") attached to this audition")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Independent copy for this audition · sent with this tape.")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                HeadshotStore.removeAuditionHeadshots(for: auditionID)
                                store.headshotVersion += 1
                                store.syncHeadshotPieces()
                                Haptics.warning()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Remove")
                                }
                                .font(.otFootnote.weight(.semibold))
                                .foregroundStyle(OT.danger)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(OT.fillField, in: Capsule())
                            }
                        }
                        .padding(14)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(OT.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Headshots are optional")
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    Text("You can skip headshots, attach your default profile photo, or take a new one.")
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                            }
                            if profileTaken > 0 {
                                Button {
                                    HeadshotStore.copyProfileHeadshots(to: auditionID)
                                    store.headshotVersion += 1
                                    store.syncHeadshotPieces()
                                    Haptics.success()
                                } label: {
                                    Label("Attach default profile photo", systemImage: "doc.on.doc")
                                        .font(.otSubhead.weight(.semibold))
                                        .foregroundStyle(OT.accent)
                                        .frame(maxWidth: .infinity, minHeight: 38)
                                        .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        .padding(14)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.square.fill")
                            .font(.title3)
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default profile headshots")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text("These are your default actor headshots. Auditions can attach them or use their own photos.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 10) {
                    slot("Front", done: taken >= 1, big: true)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        slot("Left profile", done: taken >= 2, big: false)
                        slot("Right profile", done: taken >= 3, big: false)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 300)

                if taken > 0 {
                    Button {
                        framingRatio = .headshot
                    } label: {
                        HStack(spacing: 8) {
                            if isFraming { ProgressView() }
                            Text(isFraming ? "Framing…" : "Auto-frame headshots")
                        }
                    }
                    .buttonStyle(.otSecondary)
                    .disabled(isFraming)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 120)
        }
        .id(store.headshotVersion)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let auditionID {
                    Button(taken > 0 ? "Continue" : "Skip & continue") {
                        store.continueAudition(auditionID)
                    }
                    .buttonStyle(.otPrimary)

                    HStack(spacing: 12) {
                        Button(taken < 3 ? "Camera" : "Retake camera") { store.camera = .headshot(auditionID: auditionID) }
                            .buttonStyle(.otSecondary)

                        PhotosPicker(selection: Binding(
                            get: { nil },
                            set: { (item: PhotosPickerItem?) in
                                guard let item else { return }
                                Task {
                                    if let data = try? await item.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        await MainActor.run {
                                            let nextKey = HeadshotStore.angles.first { !HeadshotStore.exists(key: $0.key, auditionID: auditionID) }?.key ?? "front"
                                            HeadshotStore.save(image, key: nextKey, auditionID: auditionID)
                                            store.headshotVersion += 1
                                            store.syncHeadshotPieces()
                                            Haptics.success()
                                        }
                                    }
                                }
                            }
                        ), matching: .images) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle")
                                Text("Pick from Photos")
                            }
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                } else {
                    Button(taken == 0 ? "Take with Camera" : taken < 3 ? "Add profiles (Camera)" : "Retake with Camera") {
                        store.camera = .headshot(auditionID: nil)
                    }
                    .buttonStyle(.otPrimary)

                    PhotosPicker(selection: Binding(
                        get: { nil },
                        set: { (item: PhotosPickerItem?) in
                            guard let item else { return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run {
                                        let nextKey = HeadshotStore.angles.first { !HeadshotStore.exists(key: $0.key, auditionID: nil) }?.key ?? "front"
                                        HeadshotStore.save(image, key: nextKey, auditionID: nil)
                                        store.headshotVersion += 1
                                        store.syncHeadshotPieces()
                                        Haptics.success()
                                    }
                                }
                            }
                        }
                    ), matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Pick from Photos")
                        }
                        .font(.otHeadline)
                        .foregroundStyle(OT.labelPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(OT.gutter)
        }
        .onAppear { store.syncHeadshotPieces() }
        .sheet(item: $adjustItem) { item in
            HeadshotAdjustSheet(item: item)
        }
        .sheet(item: $framingRatio) { ratio in
            FramingRatioSheet(ratio: ratio) { selectedRatio in
                framingRatio = nil
                isFraming = true
                // Always reframe from the original capture, so applying again (or a different
                // ratio) re-crops the full photo instead of zooming further into the last crop.
                let keys = HeadshotStore.taken(auditionID: auditionID).map(\.key)
                let originals = keys.compactMap { key in HeadshotStore.loadOriginal(key: key, auditionID: auditionID).map { (key, $0) } }
                Task.detached(priority: .userInitiated) {
                    let framed = originals.compactMap { key, image in
                        let isProfile = (key == "left" || key == "right")
                        // Profile slots have an aspect ratio of ~1.18 - 1.21.
                        // Front slot uses the selectedRatio (e.g. 4:5 or custom).
                        // Applying a vertical ratio to profile cards chops 35% of head/chin;
                        // use 1.18 for profiles so head, hair, and chin fit comfortably.
                        let ratio = isProfile ? 1.18 : selectedRatio
                        return ImageFramer.crop(image, ratio: ratio, isProfile: isProfile).map { (key, $0) }
                    }
                    await MainActor.run {
                        for (key, image) in framed { HeadshotStore.replace(image, key: key, auditionID: auditionID) }
                        store.headshotVersion += 1
                        isFraming = false
                        if framed.isEmpty { Haptics.warning() } else { Haptics.success() }
                    }
                }
            }
        }
    }

    private struct FramingRatioSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State var ratio: FramingRatio
        let apply: (CGFloat) -> Void
        @State private var customWidth = "4"
        @State private var customHeight = "5"
        @State private var useCustom = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Auto-frame photos").font(.otTitle)
                Text("Frames head and shoulders around your face, from the original photo. Run it again any time — it never crops a crop.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)
                Picker("Ratio", selection: $ratio) {
                    ForEach(FramingRatio.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use custom ratio", isOn: $useCustom)
                HStack {
                    TextField("Width", text: $customWidth).keyboardType(.numberPad)
                    Text(":").foregroundStyle(OT.labelTertiary)
                    TextField("Height", text: $customHeight).keyboardType(.numberPad)
                }
                .padding(12)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Button("Apply") {
                    let width = CGFloat(Double(customWidth) ?? 0)
                    let height = CGFloat(Double(customHeight) ?? 0)
                    apply(useCustom && width > 0 && height > 0 ? width / height : ratio.value)
                }.buttonStyle(.otPrimary)
                Button("Cancel") { dismiss() }.buttonStyle(.otSecondary)
            }
            .padding(OT.gutter)
            .presentationDetents([.height(300)])
        }
    }

    @ViewBuilder
    private func slot(_ title: String, done: Bool, big: Bool) -> some View {
        let key = title == "Front" ? "front" : title == "Left profile" ? "left" : "right"
        let isProfile = (key == "left" || key == "right")

        if done {
            Button {
                adjustItem = HeadshotAdjustItem(key: key, title: title, isProfile: isProfile, auditionID: auditionID)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    HeadshotImage(realKey: key, auditionID: auditionID)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    HStack {
                        Label(title, systemImage: "checkmark")
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "crop")
                                .font(.system(size: 11, weight: .bold))
                            Text("Adjust")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(.black.opacity(0.45), in: Capsule())
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            PhotosPicker(selection: Binding(
                get: { nil },
                set: { (item: PhotosPickerItem?) in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                HeadshotStore.save(image, key: key, auditionID: auditionID)
                                store.headshotVersion += 1
                                store.syncHeadshotPieces()
                                Haptics.success()
                            }
                        }
                    }
                }
            ), matching: .images) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(OT.labelTertiary)
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: big ? 28 : 20))
                            .foregroundStyle(OT.accent)
                        Text(title)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text("Pick from Photos")
                            .font(.otCaption)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 09 Headshot capture: front → left → right → crop

struct HeadshotFlow: View {
    enum Angle: String, CaseIterable { case front = "Front", left = "Left", right = "Right" }

    var auditionID: Audition.ID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var cameraSpeaker = CameraGuidanceSpeaker()
    @State private var voiceAllowed = false
    @State private var voiceGuidanceEnabled = true
    @State private var showMatchGuide = false
    @State private var showGhostOverlay = true
    @State private var angle: Angle = .front
    @State private var justCaptured = false
    @State private var captureFailed = false

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)

            // Alignment overlay — ghost outline to position against, shifted per angle.
            if showGhostOverlay {
                ghostAlignmentOverlay
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                    }
                    .accessibilityLabel("Close")

                    Spacer()

                    Picker("Angle", selection: $angle) {
                        ForEach(Angle.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Spacer()

                    // Reference model button — tap to inspect target headshot reference & standards.
                    referenceThumbnail
                }
                .frame(height: 44)
                .padding(.top, 8)

                Spacer()

                // Live status chips (lighting & angle)
                statusChips
                    .padding(.bottom, 6)

                Text(guide.message)
                    .font(.otHeadline).foregroundStyle(guide.aligned ? OT.success : .white)
                Text(follower.isListening ? "Tap, or say “Now”" : "Voice is off — tap the shutter")
                    .font(.otFootnote).foregroundStyle(.white.opacity(0.7))

                ZStack {
                    Button { capture() } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78))
                    }
                    .scaleEffect(justCaptured ? 0.88 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: justCaptured)
                    .accessibilityLabel("Take photo")

                    HStack {
                        // Voice guidance speaker toggle (symmetric with camera flip)
                        Button {
                            voiceGuidanceEnabled.toggle()
                            Haptics.tick()
                            if voiceGuidanceEnabled {
                                cameraSpeaker.speak("Voice guidance on", minInterval: 0.1)
                            } else {
                                cameraSpeaker.stop()
                            }
                        } label: {
                            Image(systemName: voiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundStyle(voiceGuidanceEnabled ? OT.due : .white.opacity(0.7))
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                        }
                        .accessibilityLabel(voiceGuidanceEnabled ? "Mute voice guidance" : "Turn on voice guidance")

                        Spacer()

                        Button {
                            camera.switchCamera()
                            Haptics.tick()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                        }
                        .disabled(camera.state != .ready)
                        .accessibilityLabel("Switch camera")
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMatchGuide) {
            HeadshotReferenceGuideSheet(
                angle: angle,
                auditionID: auditionID,
                showGhostOverlay: $showGhostOverlay,
                voiceGuidanceEnabled: $voiceGuidanceEnabled
            )
        }
        .task {
            camera.wantsFaceGuidance = true
            if await CameraController.requestVideoAccess() { camera.configure(position: .front) }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
            if voiceGuidanceEnabled {
                let initialPrompt: String
                switch angle {
                case .front: initialPrompt = "Front headshot. Look straight at the camera."
                case .left:  initialPrompt = "Left profile. Turn your head to your left."
                case .right: initialPrompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(initialPrompt, minInterval: 0.8)
            }
            // Continuous guidance speaker loop to keep assisting actors whose heads are turned
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                if voiceGuidanceEnabled, camera.state == .ready {
                    speakCurrentGuidance()
                }
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: guide.message) { _, _ in
            speakCurrentGuidance()
        }
        .onChange(of: angle) { _, newAngle in
            follower.reset()
            if voiceGuidanceEnabled {
                let prompt: String
                switch newAngle {
                case .front: prompt = "Front headshot. Look straight at the camera."
                case .left:  prompt = "Left profile. Turn your head to your left."
                case .right: prompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "now" || cmd?.word == "action" { capture() }
        }
        // Volume buttons, Camera Control and AirPods stem press work as the shutter.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { capture() }
        }
        .onDisappear {
            cameraSpeaker.stop()
            camera.stop()
            follower.stop()
            store.syncHeadshotPieces()
        }
        .alert("Couldn’t take that photo", isPresented: $captureFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private var ghostAlignmentOverlay: some View {
        ZStack {
            Ellipse()
                .stroke(guide.aligned ? OT.success : OT.due, lineWidth: guide.aligned ? 3 : 1.5)
                .frame(width: 200, height: 270)
                .rotation3DEffect(.degrees(angle == .front ? 0 : 8), axis: (x: 0, y: 1, z: 0))

            // Eye-line alignment notches inside the ellipse
            HStack {
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2)
                Spacer()
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2)
            }
            .frame(width: 170)
            .offset(y: -24)
        }
        .offset(x: angle == .left ? -14 : angle == .right ? 14 : 0, y: -20)
        .animation(.easeOut(duration: 0.15), value: guide.aligned)
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(lightColor)
                    .frame(width: 6, height: 6)
                Text(lightText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.black.opacity(0.55), in: Capsule())

            HStack(spacing: 5) {
                Circle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 6, height: 6)
                Text(angleStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.black.opacity(0.55), in: Capsule())
        }
    }

    private var lightColor: Color {
        guard let luma = camera.lightLevel else { return OT.success }
        return (luma < 0.22 || luma > 0.85) ? OT.due : OT.success
    }

    private var lightText: String {
        guard let luma = camera.lightLevel else { return "Light: Good" }
        if luma < 0.22 { return "Low light" }
        if luma > 0.85 { return "Direct glare" }
        return "Light: Soft & even"
    }

    private var angleStatusText: String {
        switch angle {
        case .front: return guide.aligned ? "Angle: Square" : "Face forward"
        case .left:  return guide.aligned ? "Angle: 90° profile" : "Turn left"
        case .right: return guide.aligned ? "Angle: 90° profile" : "Turn right"
        }
    }

    private func speakCurrentGuidance(immediate: Bool = false) {
        guard voiceGuidanceEnabled, camera.state == .ready else { return }
        cameraSpeaker.speak(guide.spoken, minInterval: immediate ? 0.2 : 2.0, repeatInterval: 4.5)
    }

    private var failureMessage: String {
        switch camera.state {
        case .failed(let reason): reason
        case .idle: "The camera hasn’t started. Check Settings › OneTake › Camera is on, then reopen this screen."
        default: "The camera wasn’t ready. Give it a second, then try again."
        }
    }

    /// Live coaching from face detection: is the face framed, the right size, and turned the right amount?
    private var guide: (message: String, spoken: String, aligned: Bool) {
        guard let f = camera.face else {
            return ("Show your face to the camera", "Step into the frame so your face is visible", false)
        }
        if f.height < 0.20 {
            return ("Move closer", "Move closer to the camera", false)
        }
        if f.height > 0.52 {
            return ("Move back a little", "Move back a little", false)
        }
        if f.centerX < 0.38 {
            return ("Too far left — move right", "Move to your right", false)
        }
        if f.centerX > 0.62 {
            return ("Too far right — move left", "Move to your left", false)
        }
        if f.centerY < 0.28 {
            return ("Tilt the phone up a little", "Tilt the phone up a little", false)
        }
        if f.centerY > 0.58 {
            return ("Tilt the phone down a little", "Tilt the phone down a little", false)
        }
        let yaw = f.yaw ?? 0
        switch angle {
        case .front:
            if abs(yaw) > 0.25 {
                return ("Look straight at the camera", "Look straight at the camera", false)
            }
        case .left:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your left", "Turn your head to your left", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        case .right:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your right", "Turn your head to your right", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        }
        return ("Hold still — that’s it", "Hold still — say Now to shoot", true)
    }

    private var referenceThumbnail: some View {
        Button {
            showMatchGuide = true
            Haptics.tick()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(showMatchGuide ? OT.due : .white.opacity(0.28), lineWidth: 1.5)
                        )

                    if let img = thumbnailImageForCurrentOrPriorAngle() {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: referenceSymbol)
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Mini "info" indicator badge in bottom right corner of the thumbnail
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(OT.due)
                                .background(Circle().fill(.black.opacity(0.7)))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)

                HStack(spacing: 2) {
                    Text("Match this")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match this reference guide for \(angle.rawValue)")
    }

    private func thumbnailImageForCurrentOrPriorAngle() -> UIImage? {
        if let current = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
            return current
        }
        if angle == .left, let front = HeadshotStore.load(key: "Front", auditionID: auditionID) {
            return front
        }
        if angle == .right {
            return HeadshotStore.load(key: "Left", auditionID: auditionID) ?? HeadshotStore.load(key: "Front", auditionID: auditionID)
        }
        return nil
    }

    private var referenceSymbol: String {
        switch angle {
        case .front: "person.crop.circle"
        case .left:  "person.crop.circle.badge.checkmark"
        case .right: "person.crop.circle.badge.checkmark"
        }
    }

    private func capture() {
        guard !justCaptured else { return }
        justCaptured = true
        cameraSpeaker.stop()
        camera.capturePhoto { image in
            justCaptured = false
            guard let image else { captureFailed = true; Haptics.warning(); return }
            HeadshotStore.save(image, key: angle.rawValue, auditionID: auditionID)
            store.headshotVersion += 1
            store.syncHeadshotPieces()
            Haptics.success()
            if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
                let saved = angle.rawValue
                let nextName = next.rawValue
                angle = next
                follower.reset()
                if voiceGuidanceEnabled {
                    let prompt = next == .left ? "\(saved) photo saved. Now turn to your left profile." : "\(saved) photo saved. Now turn to your right profile."
                    cameraSpeaker.speak(prompt, minInterval: 0.1)
                }
            } else {
                if voiceGuidanceEnabled {
                    cameraSpeaker.speak("All headshots saved!", minInterval: 0.1)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Match Reference Guide Sheet

struct HeadshotReferenceGuideSheet: View {
    let angle: HeadshotFlow.Angle
    var auditionID: Audition.ID? = nil
    @Binding var showGhostOverlay: Bool
    @Binding var voiceGuidanceEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Match Reference", backLabel: "Done", onDark: true, onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)

            ScrollView {
                VStack(spacing: 20) {
                    // Header Card with angle illustration / preview
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 200)

                            if let saved = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
                                Image(uiImage: saved)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                referencePoseIllustration
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        Text(angleTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        Text(angleSummary)
                            .font(.otSubhead)
                            .foregroundStyle(OT.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.top, 8)

                    // Casting Standards Checklist
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Casting Standards")
                            .font(.otHeadline)
                            .foregroundStyle(.white)

                        guideRow(icon: "eye.fill", title: "Eye-line Alignment", desc: "Align eyes level with the horizontal guide notches. Look straight at the camera lens.")
                        guideRow(icon: "arrow.triangle.2.circlepath", title: "Head Angle", desc: angleAngleDesc)
                        guideRow(icon: "sun.max.fill", title: "Soft & Even Lighting", desc: "Face a window or soft key light. Avoid harsh backlights, hard shadows, or overhead glare.")
                        guideRow(icon: "viewfinder", title: "Framing & Distance", desc: "Hold phone 2–3 feet away at chin level. Head and shoulders should fill the frame with 1–2 inches headroom.")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Overlay & Voice Guidance Toggles
                    VStack(spacing: 12) {
                        Toggle(isOn: $showGhostOverlay) {
                            Label("Show Alignment Overlay", systemImage: "viewfinder")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)

                        Divider().overlay(Color.white.opacity(0.1))

                        Toggle(isOn: $voiceGuidanceEnabled) {
                            Label("Spoken Voice Guidance", systemImage: "speaker.wave.2.fill")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        dismiss()
                    } label: {
                        Text("Got it — Start Matching")
                            .font(.otHeadline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(OT.due, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(OT.gutter)
            }
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var angleTitle: String {
        switch angle {
        case .front: "Front Headshot"
        case .left:  "Left 90° Profile"
        case .right: "Right 90° Profile"
        }
    }

    private var angleSummary: String {
        switch angle {
        case .front: "Direct front-facing portrait. Shoulders square, eyes looking straight at the camera with chin level."
        case .left:  "Full 90-degree turn to your left. Your left ear, nose profile, and jawline should be clearly defined."
        case .right: "Full 90-degree turn to your right. Your right ear, nose profile, and jawline should be clearly defined."
        }
    }

    private var angleAngleDesc: String {
        switch angle {
        case .front: "Face the lens squarely. Keep head level without tilting left or right."
        case .left:  "Turn head 90° to your left until only your left profile is visible. Keep chin parallel to ground."
        case .right: "Turn head 90° to your right until only your right profile is visible. Keep chin parallel to ground."
        }
    }

    private func guideRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OT.due)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var referencePoseIllustration: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(OT.due.opacity(0.4), lineWidth: 2)
                    .frame(width: 90, height: 90)

                Image(systemName: angle == .front ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(OT.due)
                    .scaleEffect(x: angle == .left ? -1 : 1, y: 1)
            }
            Text("Reference Pose Guide")
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(OT.labelTertiary)
        }
        .frame(height: 180)
    }
}

// MARK: - 10 Interactive Headshot Resizing & Framing Sheet

struct HeadshotAdjustItem: Identifiable {
    let key: String
    let title: String
    let isProfile: Bool
    var auditionID: UUID? = nil
    var id: String { "\(key)-\(auditionID?.uuidString ?? "profile")" }
}

struct HeadshotAdjustSheet: View {
    let item: HeadshotAdjustItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    @State private var originalImage: UIImage?
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var photoItem: PhotosPickerItem?
    @State private var isAutoFraming = false

    /// Display frame dimensions inside the sheet matching slot proportions.
    /// Front slot is 175.5 x 300 (ratio 0.585).
    /// Profile slots are 175.5 x 145 (ratio 1.21).
    private var frameSize: CGSize {
        if item.isProfile {
            return CGSize(width: 312, height: 260)
        } else {
            return CGSize(width: 216, height: 370)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(
                title: "Adjust \(item.title)",
                backLabel: "Cancel",
                onDark: true,
                onBack: { dismiss() }
            ) {
                Button("Save") { saveCrop() }
                    .font(.otHeadline)
                    .foregroundStyle(OT.accent)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color.black)

            // Viewport area
            ZStack {
                Color.black.ignoresSafeArea()

                if let img = originalImage {
                    let baseScale = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
                    let currentZoom = max(1.0, min(zoom * pinchScale, 4.0))
                    let effectiveOffset = clampOffset(
                        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height),
                        zoomFactor: currentZoom
                    )

                    // Clamped crop frame
                    ZStack {
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: img.size.width * baseScale * currentZoom,
                                   height: img.size.height * baseScale * currentZoom)
                            .offset(effectiveOffset)

                        // Rule of thirds subtle grid guides
                        gridLines

                        // Corner crop brackets
                        cornerBrackets
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { val in dragOffset = val.translation }
                                .onEnded { val in
                                    offset = clampOffset(
                                        CGSize(width: offset.width + val.translation.width, height: offset.height + val.translation.height),
                                        zoomFactor: zoom
                                    )
                                    dragOffset = .zero
                                },
                            MagnificationGesture()
                                .onChanged { val in pinchScale = val }
                                .onEnded { val in
                                    zoom = max(1.0, min(zoom * val, 4.0))
                                    pinchScale = 1.0
                                    offset = clampOffset(offset, zoomFactor: zoom)
                                }
                        )
                    )
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom control panel
            VStack(spacing: 16) {
                // Zoom slider
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(OT.labelTertiary)
                    Slider(value: $zoom, in: 1.0...3.5)
                        .tint(OT.accent)
                        .onChange(of: zoom) { _, newZoom in
                            offset = clampOffset(offset, zoomFactor: newZoom)
                        }
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(.horizontal, 24)

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        autoFrame()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Auto-frame")
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            zoom = 1.0
                            offset = .zero
                            dragOffset = .zero
                            pinchScale = 1.0
                        }
                        Haptics.tick()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Menu {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            dismiss()
                            store.camera = .headshot(auditionID: item.auditionID)
                        } label: {
                            Label("Take with Camera", systemImage: "camera")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Replace")
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, OT.gutter)

                Text(item.isProfile
                     ? "Drag to pan, pinch or slide to resize. Auto-frame keeps hair, jawline, and chin within profile bounds."
                     : "Drag to pan, pinch or slide to resize. Auto-frame centers head and shoulders with generous headroom.")
                    .font(.otCaption)
                    .foregroundStyle(OT.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .padding(.top, 14)
            .background(OT.surfaceRaised)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { loadPhoto() }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let upright = ImageFramer.normalized(img) {
                    await MainActor.run {
                        HeadshotStore.save(upright, key: item.key, auditionID: item.auditionID)
                        originalImage = upright
                        zoom = 1.0
                        offset = .zero
                        dragOffset = .zero
                        pinchScale = 1.0
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        autoFrame()
                    }
                }
            }
        }
    }

    private func loadPhoto() {
        if let raw = HeadshotStore.loadOriginal(key: item.key, auditionID: item.auditionID) ?? HeadshotStore.load(key: item.key, auditionID: item.auditionID),
           let upright = ImageFramer.normalized(raw) {
            originalImage = upright
        }
    }

    private func clampOffset(_ raw: CGSize, zoomFactor: CGFloat) -> CGSize {
        guard let img = originalImage else { return .zero }
        let base = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
        let z = max(1.0, min(zoomFactor, 4.0))
        let maxOffX = max(0, (img.size.width * base * z - frameSize.width) / 2)
        let maxOffY = max(0, (img.size.height * base * z - frameSize.height) / 2)
        return CGSize(
            width: min(max(raw.width, -maxOffX), maxOffX),
            height: min(max(raw.height, -maxOffY), maxOffY)
        )
    }

    private func autoFrame() {
        guard let img = originalImage, let cg = img.cgImage else { return }
        let imgSize = CGSize(width: cg.width, height: cg.height)
        let face = ImageFramer.detectSubject(in: cg, size: imgSize, isProfile: item.isProfile)
        let ratio = frameSize.width / frameSize.height
        let rect = ImageFramer.cropRect(imageSize: imgSize, subject: face, ratio: ratio, isProfile: item.isProfile)
        guard rect.width > 0, rect.height > 0 else { return }

        let base = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
        let pointsToPixels = CGFloat(cg.width) / img.size.width
        let targetCropWInPoints = rect.width / pointsToPixels
        let targetZoom = max(1.0, min(frameSize.width / (targetCropWInPoints * base), 4.0))

        let cropCenterInPoints = CGPoint(x: rect.midX / pointsToPixels, y: rect.midY / pointsToPixels)
        let imageCenterInPoints = CGPoint(x: img.size.width / 2, y: img.size.height / 2)

        let requiredOffsetX = (imageCenterInPoints.x - cropCenterInPoints.x) * base * targetZoom
        let requiredOffsetY = (imageCenterInPoints.y - cropCenterInPoints.y) * base * targetZoom

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoom = targetZoom
            offset = clampOffset(CGSize(width: requiredOffsetX, height: requiredOffsetY), zoomFactor: targetZoom)
            dragOffset = .zero
            pinchScale = 1.0
        }
        Haptics.tick()
    }

    private func saveCrop() {
        guard let img = originalImage, let cg = img.cgImage else { dismiss(); return }
        let base = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
        let z = max(1.0, min(zoom, 4.0))
        let effectiveOffset = clampOffset(offset, zoomFactor: z)

        let displayedW = img.size.width * base * z
        let displayedH = img.size.height * base * z

        let imageOriginX = (frameSize.width - displayedW) / 2 + effectiveOffset.width
        let imageOriginY = (frameSize.height - displayedH) / 2 + effectiveOffset.height

        let cropInPointsX = (0 - imageOriginX) / (base * z)
        let cropInPointsY = (0 - imageOriginY) / (base * z)
        let cropInPointsW = frameSize.width / (base * z)
        let cropInPointsH = frameSize.height / (base * z)

        let scaleFactor = CGFloat(cg.width) / img.size.width
        let pixelRect = CGRect(
            x: cropInPointsX * scaleFactor,
            y: cropInPointsY * scaleFactor,
            width: cropInPointsW * scaleFactor,
            height: cropInPointsH * scaleFactor
        ).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))

        guard pixelRect.width > 0, pixelRect.height > 0, let croppedCG = cg.cropping(to: pixelRect) else {
            dismiss()
            return
        }

        let croppedImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
        HeadshotStore.replace(croppedImage, key: item.key, auditionID: item.auditionID)
        store.headshotVersion += 1
        store.syncHeadshotPieces()
        Haptics.success()
        dismiss()
    }

    private var gridLines: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var cornerBrackets: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let arm: CGFloat = 16
            Path { path in
                // Top-left
                path.move(to: CGPoint(x: 0, y: arm))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))

                // Top-right
                path.move(to: CGPoint(x: w - arm, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: arm))

                // Bottom-left
                path.move(to: CGPoint(x: 0, y: h - arm))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: arm, y: h))

                // Bottom-right
                path.move(to: CGPoint(x: w - arm, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - arm))
            }
            .stroke(Color.white.opacity(0.8), lineWidth: 2.5)
        }
    }
}
