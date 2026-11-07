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
    @State private var showResumePicker = false
    @State private var resumeImportError: String?
    @AppStorage("camera.gesturesEnabled") private var showGestures = false
    @AppStorage("slateAtStart") private var slateAtStart = true
    @AppStorage("readerVolume") private var readerVolume = "Quieter"
    @AppStorage("practice.showSample") private var showSampleScene = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .center) {
                    Text("Profile").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Button("Done") {
                        store.showProfile = false
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(minHeight: 44)
                }
                .padding(.top, 16)

                // Slate & Headshot Card
                VStack(alignment: .leading, spacing: 12) {
                    Button { store.push(.editSlate) } label: {
                        HStack(spacing: 14) {
                            HeadshotImage(realKey: "front", iconSize: 28).id(store.headshotVersion)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.slate.name.isEmpty ? "Add your name" : store.slate.name).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                                Text(store.slate.summary)
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(OT.accent).frame(width: 32, height: 32).background(OT.accentSoft, in: Circle())
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

                    Divider()

                    HStack(spacing: 10) {
                        Label("Résumé", systemImage: "doc.text")
                            .font(.otBody).foregroundStyle(OT.labelPrimary)
                        Spacer(minLength: 8)
                        if let resumeURL = store.slate.resumeURL {
                            Text(resumeURL.lastPathComponent)
                                .font(.otCaption).foregroundStyle(OT.labelSecondary)
                                .lineLimit(1).truncationMode(.middle)
                            Button("Replace") { showResumePicker = true }
                                .font(.otCaption.weight(.semibold)).foregroundStyle(OT.accent)
                        } else {
                            Button("Add PDF") { showResumePicker = true }
                                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.accent)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(OT.accentSoft, in: Capsule())
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .contain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .otCard(radius: 18)

                // Every time you record
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Recording")

                    VStack(spacing: 0) {
                        Toggle(isOn: $slateAtStart) {
                            Text("Slate at the start").font(.otBody).foregroundStyle(OT.labelPrimary)
                        }
                        .tint(OT.accent)
                        .frame(minHeight: 44)

                        Divider().padding(.vertical, 2)

                        HStack {
                            Text("Reader volume").font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Picker("Reader volume", selection: $readerVolume) {
                                ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) }
                            }
                            .tint(OT.accent)
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .otCard(radius: 18)
                }

                // Practice sample
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Practice")

                    Toggle(isOn: $showSampleScene) {
                        Text("Show sample scene").font(.otBody).foregroundStyle(OT.labelPrimary)
                    }
                    .tint(OT.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .otCard(radius: 18)
                    .onChange(of: showSampleScene) { _, enabled in
                        if !enabled { store.removeSampleData(); Haptics.tick() }
                    }
                }

                // More section
                VStack(alignment: .leading, spacing: 6) {
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
                                Label("Hands-free controls", systemImage: "hand.raised")
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .otCard(radius: 18)
                }

                // Account section (moved down)
                VStack(alignment: .leading, spacing: 6) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .otCard(radius: 18)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 32)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
    @AppStorage("camera.voiceCommandsEnabled") private var voiceCommandsEnabled = true
    @AppStorage("camera.gestureHoldDuration") private var holdDuration = 1.2

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(title: "Hands-free controls", backLabel: "Done", onBack: { dismiss() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 16)

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

                    Picker("Height unit", selection: Binding(get: { heightUnit }, set: changeHeightUnit)) {
                        Text("ft / in").tag(HeightUnit.feetInches)
                        Text("cm").tag(HeightUnit.centimetres)
                    }
                    .pickerStyle(.segmented)
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
    @State private var showConfirmClearPractice = false
    @State private var showConfirmResetApp = false
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
                dataResetSection
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
        .confirmationDialog("Clear practice data?", isPresented: $showConfirmClearPractice, titleVisibility: .visible) {
            Button("Clear practice data", role: .destructive) {
                clearPractice()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Practice pieces and reader audio on this iPhone will be reset.")
        }
        .confirmationDialog("Disconnect account?", isPresented: $showConfirmDisconnectAccount, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                store.deleteAccount()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clean local media files?", isPresented: $showConfirmDeleteAll, titleVisibility: .visible) {
            Button("Delete media files", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes recorded video takes, headshots, and reader audio to free up disk space. Your audition cards and scripts are kept.")
        }
        .confirmationDialog("Erase all app data and reset?", isPresented: $showConfirmResetApp, titleVisibility: .visible) {
            Button("Erase all data and reset", role: .destructive) {
                store.resetAppForTesting()
                storageRefreshID = UUID()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently wipes every audition, take, headshot, setting, and preference on this iPhone, returning OneTake to a clean fresh install state for testing.")
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
            if readerSize > 0 || !store.practice.isEmpty {
                Button("Clear practice audio and scenes") {
                    showConfirmClearPractice = true
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
    private var dataResetSection: some View {
        Section {
            Button(role: .destructive) {
                showConfirmDeleteAll = true
            } label: {
                Label("Clean local media files", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("Clean local data")

            Button(role: .destructive) {
                showConfirmResetApp = true
            } label: {
                Label("Erase entire app data & reset", systemImage: "trash.fill")
            }
            .accessibilityIdentifier("Reset app for testing")
        } header: {
            Text("Storage & Reset")
        } footer: {
            Text("“Clean local media” deletes takes, audio, and headshots to reclaim disk space while preserving your audition cards. “Erase entire app data” wipes all auditions, settings, and files, returning OneTake to a clean fresh-install state for testing.")
        }
    }

    @ViewBuilder
    private var legalSection: some View {
        Section {
            NavigationLink("Privacy policy") { PrivacyPolicyView() }
        } footer: {
            Text("Sent tapes are not affected.")
        }
    }

    private func clearPractice() {
        store.clearPracticeData()
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        storageRefreshID = UUID()
        Haptics.success()
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
        store.clearAllLocalData()
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
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
                section("Deleting data", "Clean local data in Profile → Privacy & data. Takes, headshots, reader tracks, and practice pieces are removed from this iPhone. Previously shared iCloud links remain in your iCloud Drive.")
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
    @State private var previewItem: HeadshotViewerItem?
    @State private var pickAngle: String?
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isFraming = false
    @State private var framingPreset: HeadshotPreset = .cardSlot
    @State private var hasSavedHeadshots = false

    /// Counted from the real files on disk for this specific audition or profile
    private var taken: Int {
        HeadshotStore.taken(auditionID: auditionID).count
    }

    private var profileTaken: Int {
        HeadshotStore.taken(auditionID: nil).count
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
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3).foregroundStyle(OT.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Saved for this audition")
                                        .font(.otHeadline).foregroundStyle(OT.labelPrimary)
                                    Text("These photos stay on this iPhone and go with this tape.")
                                        .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                                }
                                Spacer(minLength: 4)
                                Button(role: .destructive) {
                                    HeadshotStore.removeAuditionHeadshots(for: auditionID)
                                    store.headshotVersion += 1
                                    store.syncHeadshotPieces()
                                    Haptics.warning()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.danger)
                                        .frame(width: 36, height: 36)
                                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .accessibilityLabel("Remove audition headshots")
                            }

                            ForEach(HeadshotStore.taken(auditionID: auditionID), id: \.key) { photo in
                                HStack(spacing: 10) {
                                    if let image = HeadshotStore.load(key: photo.key, auditionID: auditionID) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 42, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(photo.title).font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                    Spacer()
                                    Text("Crop \(savedCropRatio(for: photo.key, auditionID: auditionID))")
                                        .font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)
                                }
                                .padding(8)
                                .background(OT.bgCanvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(14)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        let isOpt = store.audition(auditionID)?.pieces.first(where: { $0.kind == .headshot })?.isOptional ?? false
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(OT.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isOpt ? "Headshots are optional" : "Audition headshots")
                                        .font(.otHeadline)
                                        .foregroundStyle(OT.labelPrimary)
                                    Text(isOpt ? "You can skip headshots, attach your default profile photo, or take a new one." : "Required for this package. Attach your default profile photo or take new ones.")
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
                    slot("Front", done: HeadshotStore.exists(key: "front", auditionID: auditionID), big: true)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        slot("Left profile", done: HeadshotStore.exists(key: "left", auditionID: auditionID), big: false)
                        slot("Right profile", done: HeadshotStore.exists(key: "right", auditionID: auditionID), big: false)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 300)

                if taken > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Menu {
                            ForEach(HeadshotPreset.allCases) { preset in
                                Button {
                                    framingPreset = preset
                                    autoFrameAllHeadshots(preset: preset)
                                } label: {
                                    if framingPreset == preset {
                                        Label(preset.title, systemImage: "checkmark")
                                    } else {
                                        Label(preset.title, systemImage: preset.icon)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isFraming { ProgressView() } else { Image(systemName: "sparkles") }
                                Text(isFraming ? "Framing…" : "Auto-frame · \(framingPreset.shortTitle)")
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(OT.labelTertiary)
                            }
                        }
                        .buttonStyle(.otSecondary)
                        .disabled(isFraming)
                    }
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
                    if taken > 0 {
                        HStack(spacing: 6) {
                            Label(hasSavedHeadshots ? "Headshots saved · Next: Slate" : "Photos ready to save", systemImage: hasSavedHeadshots ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(hasSavedHeadshots ? OT.success : OT.accent)
                            Spacer()
                        }
                        .font(.otFootnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if taken > 0 && !hasSavedHeadshots {
                        Button("Save Headshots") {
                            hasSavedHeadshots = true
                            store.syncHeadshotPieces()
                            store.syncPieces()
                            Haptics.success()
                        }
                        .buttonStyle(.otPrimary)
                    } else {
                        Button(continueButtonTitle) {
                            handleContinue(auditionID)
                        }
                        .buttonStyle(.otPrimary)
                    }

                    HStack(spacing: 12) {
                        Button(taken < 3 ? "Camera" : "Retake camera") { store.camera = .headshot(auditionID: auditionID) }
                            .buttonStyle(.otSecondary)

                        Menu {
                            Button {
                                pickAngle = "front"
                                showPicker = true
                            } label: {
                                Label("Front Headshot", systemImage: HeadshotStore.exists(key: "front", auditionID: auditionID) ? "checkmark.circle.fill" : "circle")
                            }
                            Button {
                                pickAngle = "left"
                                showPicker = true
                            } label: {
                                Label("Left Profile", systemImage: HeadshotStore.exists(key: "left", auditionID: auditionID) ? "checkmark.circle.fill" : "circle")
                            }
                            Button {
                                pickAngle = "right"
                                showPicker = true
                            } label: {
                                Label("Right Profile", systemImage: HeadshotStore.exists(key: "right", auditionID: auditionID) ? "checkmark.circle.fill" : "circle")
                            }
                        } label: {
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

                    Menu {
                        Button {
                            pickAngle = "front"
                            showPicker = true
                        } label: {
                            Label("Front Headshot", systemImage: HeadshotStore.exists(key: "front", auditionID: nil) ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            pickAngle = "left"
                            showPicker = true
                        } label: {
                            Label("Left Profile", systemImage: HeadshotStore.exists(key: "left", auditionID: nil) ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            pickAngle = "right"
                            showPicker = true
                        } label: {
                            Label("Right Profile", systemImage: HeadshotStore.exists(key: "right", auditionID: nil) ? "checkmark.circle.fill" : "circle")
                        }
                    } label: {
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
        .onAppear {
            hasSavedHeadshots = taken > 0
            store.syncHeadshotPieces()
            store.syncPieces()
            if ProcessInfo.processInfo.arguments.contains("-testHeadshotAdjust") {
                adjustItem = HeadshotAdjustItem(key: "front", title: "Front", isProfile: false, auditionID: auditionID)
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem, let key = pickAngle else { return }
            let title = key == "front" ? "Front" : key == "left" ? "Left profile" : "Right profile"
            let isProfile = (key == "left" || key == "right")
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        HeadshotStore.save(image, key: key, auditionID: auditionID)
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        Haptics.success()
                        pickerItem = nil
                        pickAngle = nil
                        // Immediately open adjustment for the picked photo so user can frame it!
                        adjustItem = HeadshotAdjustItem(key: key, title: title, isProfile: isProfile, auditionID: auditionID)
                    }
                }
            }
        }
        .sheet(item: $previewItem) { item in
            HeadshotViewerSheet(item: item, onAdjust: {
                adjustItem = HeadshotAdjustItem(key: item.key, title: item.title, isProfile: item.isProfile, auditionID: item.auditionID)
            })
        }
        .sheet(item: $adjustItem) { item in
            HeadshotAdjustSheet(item: item)
        }
    }

    private func autoFrameAllHeadshots(preset: HeadshotPreset = .cardSlot) {
        isFraming = true
        let keys = HeadshotStore.taken(auditionID: auditionID).map(\.key)
        let originals = keys.compactMap { key in HeadshotStore.loadOriginal(key: key, auditionID: auditionID).map { (key, $0) } }
        Task.detached(priority: .userInitiated) {
            let framed = originals.compactMap { key, image in
                let isProfile = (key == "left" || key == "right")
                return ImageFramer.crop(image, preset: preset, isProfile: isProfile).map { (key, $0) }
            }
            await MainActor.run {
                for (key, image) in framed { HeadshotStore.replace(image, key: key, auditionID: auditionID) }
                store.headshotVersion += 1
                isFraming = false
                if framed.isEmpty { Haptics.warning() } else { Haptics.success() }
            }
        }
    }

    /// The app stores one current crop per headshot; report its real pixel ratio instead of
    /// suggesting that several export sizes have already been generated.
    private func savedCropRatio(for key: String, auditionID: Audition.ID) -> String {
        guard let image = HeadshotStore.load(key: key, auditionID: auditionID), image.size.height > 0 else { return "Unknown" }
        let ratio = image.size.width / image.size.height
        let known: [(CGFloat, String)] = [(4.0 / 5.0, "4:5"), (3.0 / 4.0, "3:4"), (1.0, "1:1")]
        return known.first(where: { abs($0.0 - ratio) < 0.035 })?.1 ?? "Custom"
    }

    private var continueButtonTitle: String {
        guard let auditionID else { return "Continue" }
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasPackage = store.currentPath.contains {
            if case .package(let id) = $0, id == auditionID { return true }
            return false
        }

        if hasPreview {
            return taken > 0 ? "Back to preview" : "Skip & back to preview"
        } else if hasTapeCheck {
            return taken > 0 ? "Back to tape check" : "Skip & back to tape check"
        } else if hasPackage {
            return taken > 0 ? "Back to package" : "Skip & back to package"
        } else {
            guard let audition = store.audition(auditionID) else {
                return taken > 0 ? "Continue" : "Skip & continue"
            }
            guard !audition.isPackageReady, let next = audition.nextPiece else { return "Continue to preview" }
            switch next.kind {
            case .slate: return taken > 0 ? "Continue to slate" : "Skip headshots · go to slate"
            case .fullLength: return taken > 0 ? "Continue to full-body shot" : "Skip headshots · go to full-body shot"
            case .scene: return taken > 0 ? "Continue to \(next.title)" : "Skip headshots · go to \(next.title)"
            case .headshot: return taken > 0 ? "Continue" : "Skip & continue"
            }
        }
    }

    private var nextStepAfterHeadshots: String? {
        guard let auditionID, let audition = store.audition(auditionID) else { return nil }
        guard !audition.isPackageReady, let next = audition.nextPiece else { return "Preview" }
        switch next.kind {
        case .headshot: return "more headshots"
        case .slate: return "slate"
        case .fullLength: return "full-body shot"
        case .scene: return next.title
        }
    }

    private func handleContinue(_ id: Audition.ID) {
        store.syncPieces()

        // If we came from Preview, pop back to Preview
        if store.currentPath.contains(where: {
            if case .preview(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.preview(id))
            return
        }

        // If we came from Tape Check, pop back to Tape Check
        if store.currentPath.contains(where: {
            if case .tapeCheck(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.tapeCheck(id))
            return
        }

        // If we came from Package, pop back to Package
        if store.currentPath.contains(where: {
            if case .package(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.package(id))
            return
        }

        // If all required pieces are completed, advance to Preview
        guard let a = store.audition(id) else { return }
        if a.isPackageReady {
            // Leave the camera/photo editing route behind the audition overview. Otherwise Back
            // from Preview can land on Headshots even though that editing task is complete.
            if store.currentPath.contains(.auditionDetail(id)) {
                store.popTo(.auditionDetail(id))
            } else {
                store.popToRoot()
            }
            store.push(.preview(id))
            return
        }

        store.continueAudition(id)
    }

    @ViewBuilder
    private func slot(_ title: String, done: Bool, big: Bool) -> some View {
        let key = title == "Front" ? "front" : title == "Left profile" ? "left" : "right"
        let isProfile = (key == "left" || key == "right")

        if done {
            ZStack(alignment: .bottomLeading) {
                // Tapping the photo opens the inspection viewer so the actor can check it out
                HeadshotImage(realKey: key, auditionID: auditionID)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        previewItem = HeadshotViewerItem(key: key, title: title, isProfile: isProfile, auditionID: auditionID)
                    }

                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)

                HStack {
                    Label(title, systemImage: "checkmark")
                        .font(.otFootnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    // Tapping Adjust opens the crop tool directly
                    Button {
                        adjustItem = HeadshotAdjustItem(key: key, title: title, isProfile: isProfile, auditionID: auditionID)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "crop")
                                .font(.system(size: 11, weight: .bold))
                            Text("Adjust")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(.black.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Button {
                pickAngle = key
                showPicker = true
            } label: {
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
    @State private var comparisonPhotos: [UIImage] = []
    @State private var selectedComparisonPhoto = 1
    @State private var showingComparison = false

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

                Text(comparisonPhotos.isEmpty ? guide.message : "Take one more to compare")
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

            if showingComparison {
                HeadshotComparisonView(
                    title: angle.rawValue,
                    photos: comparisonPhotos,
                    selectedIndex: $selectedComparisonPhoto,
                    onKeep: keepSelectedComparisonPhoto,
                    onRetry: retryComparisonPhoto
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
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
        guard !justCaptured, !showingComparison else { return }
        justCaptured = true
        cameraSpeaker.stop()
        camera.capturePhoto { image in
            justCaptured = false
            guard let image else { captureFailed = true; Haptics.warning(); return }
            Haptics.success()
            if comparisonPhotos.isEmpty, let prior = HeadshotStore.load(key: angle.rawValue, auditionID: auditionID) {
                comparisonPhotos = [prior, image]
                selectedComparisonPhoto = 1
                showingComparison = true
            } else {
                comparisonPhotos.append(image)
                if comparisonPhotos.count >= 2 {
                    selectedComparisonPhoto = comparisonPhotos.count - 1
                    showingComparison = true
                } else if voiceGuidanceEnabled {
                    cameraSpeaker.speak("Good. Take one more so you can compare.", minInterval: 0.1)
                }
            }
        }
    }

    private func keepSelectedComparisonPhoto() {
        guard comparisonPhotos.indices.contains(selectedComparisonPhoto) else { return }
        HeadshotStore.save(comparisonPhotos[selectedComparisonPhoto], key: angle.rawValue, auditionID: auditionID)
        store.headshotVersion += 1
        store.syncHeadshotPieces()
        comparisonPhotos.removeAll()
        showingComparison = false
        Haptics.success()
        if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
            let saved = angle.rawValue
            angle = next
            follower.reset()
            if voiceGuidanceEnabled {
                let prompt = next == .left ? "\(saved) photo saved. Now turn to your left profile." : "\(saved) photo saved. Now turn to your right profile."
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        } else {
            if voiceGuidanceEnabled { cameraSpeaker.speak("All headshots saved!", minInterval: 0.1) }
            dismiss()
        }
    }

    private func retryComparisonPhoto() {
        if comparisonPhotos.count > 1 { comparisonPhotos = [comparisonPhotos[selectedComparisonPhoto]] }
        selectedComparisonPhoto = 0
        showingComparison = false
        Haptics.tick()
    }
}

/// Lets the actor compare two captures for one headshot angle before saving either one.
private struct HeadshotComparisonView: View {
    let title: String
    let photos: [UIImage]
    @Binding var selectedIndex: Int
    let onKeep: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onRetry) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OT.cameraLabel)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.85), in: Circle())
                }
                .accessibilityLabel("Return to camera")
                Spacer()
                Text("\(title) · \(photos.count) shots")
                    .font(.otHeadline).foregroundStyle(OT.cameraLabel)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20).padding(.top, 12)

            VStack(alignment: .leading, spacing: 5) {
                Text("Keep the better one").font(.system(size: 22, weight: .semibold)).foregroundStyle(OT.cameraLabel)
                Text("Compare the headshots side by side").font(.otCallout).foregroundStyle(OT.cameraLabel2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)

            HStack(alignment: .top, spacing: 12) {
                ForEach(photos.indices, id: \.self) { index in
                    Button { selectedIndex = index } label: {
                        VStack(spacing: 8) {
                            Image(uiImage: photos[index])
                                .resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 219)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: selectedIndex == index ? "checkmark.circle.fill" : "circle")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(selectedIndex == index ? Color(red: 0.56, green: 0.38, blue: 0.06) : OT.cameraLabel2)
                                        .padding(8)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selectedIndex == index ? Color(red: 0.56, green: 0.38, blue: 0.06) : Color.clear, lineWidth: 2))
                            Text("Take \(index + 1)").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.cameraLabel)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select take \(index + 1)")
                }
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 9) {
                comparisonNote("sun.max", "Compare for soft, even light")
                comparisonNote("viewfinder", "Check that your face is centred")
                comparisonNote("exclamationmark.circle", "Look for a plain background and eye-level camera")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 18)

            Spacer(minLength: 16)
            VStack(spacing: 10) {
                Button("Keep take \(selectedIndex + 1)", action: onKeep)
                    .buttonStyle(.otPrimary)
                Button("Try again", action: onRetry)
                    .font(.otHeadline).foregroundStyle(OT.accent)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color(red: 0.91, green: 0.85, blue: 0.95), in: Capsule())
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.965, green: 0.957, blue: 0.972).ignoresSafeArea())
    }

    private func comparisonNote(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbol == "exclamationmark.circle" ? OT.due : OT.success)
            Text(text).font(.otFootnote).foregroundStyle(OT.cameraLabel2)
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
    @State private var selectedPreset: HeadshotPreset = .cardSlot
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var photoItem: PhotosPickerItem?
    @State private var isAutoFraming = false
    @State private var saveError = false

    /// Display frame dimensions inside the sheet matching slot proportions or selected preset ratio.
    private func targetFrameSize(for preset: HeadshotPreset) -> CGSize {
        let maxW: CGFloat = 300
        let maxH: CGFloat = 380
        let r = preset.ratio(isProfile: item.isProfile)
        if r > (maxW / maxH) {
            return CGSize(width: maxW, height: maxW / r)
        } else {
            return CGSize(width: maxH * r, height: maxH)
        }
    }

    private var frameSize: CGSize {
        targetFrameSize(for: selectedPreset)
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

            // Bottom control panel: one preset menu, plus direct pinch/drag framing.
            VStack(spacing: 12) {
                Menu {
                    ForEach(HeadshotPreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                            autoFrame(preset: preset, animated: true)
                        } label: {
                            if selectedPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Label(preset.title, systemImage: preset.icon)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Auto-frame · \(selectedPreset.title)")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, OT.gutter)

                // Preset description helper
                Text("Choose a preset, then pinch or drag the photo to fine-tune its size and position.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        autoFrame(preset: selectedPreset, animated: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Re-frame")
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
                        autoFrame(preset: selectedPreset)
                    }
                }
            }
        }
        .alert("Couldn't save this headshot crop", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original photo is still saved. Try adjusting the crop and saving again.")
        }
    }

    private func loadPhoto() {
        if let raw = HeadshotStore.loadOriginal(key: item.key, auditionID: item.auditionID) ?? HeadshotStore.load(key: item.key, auditionID: item.auditionID),
           let upright = ImageFramer.normalized(raw) {
            originalImage = upright
            if !HeadshotStore.hasOriginal(key: item.key, auditionID: item.auditionID) {
                autoFrame(preset: selectedPreset, animated: false)
            }
        }
    }

    private func clampOffset(_ raw: CGSize, zoomFactor: CGFloat, customFrame: CGSize? = nil) -> CGSize {
        guard let img = originalImage else { return .zero }
        let target = customFrame ?? frameSize
        let base = max(target.width / img.size.width, target.height / img.size.height)
        let z = max(1.0, min(zoomFactor, 4.0))
        let maxOffX = max(0, (img.size.width * base * z - target.width) / 2)
        let maxOffY = max(0, (img.size.height * base * z - target.height) / 2)
        return CGSize(
            width: min(max(raw.width, -maxOffX), maxOffX),
            height: min(max(raw.height, -maxOffY), maxOffY)
        )
    }

    private func autoFrame(preset: HeadshotPreset? = nil, animated: Bool = true) {
        let targetPreset = preset ?? selectedPreset
        guard let img = originalImage, let cg = img.cgImage else { return }
        let imgSize = CGSize(width: cg.width, height: cg.height)
        let face = ImageFramer.detectSubject(in: cg, size: imgSize, isProfile: item.isProfile)
        let ratio = targetPreset.ratio(isProfile: item.isProfile)
        let rect = ImageFramer.cropRect(imageSize: imgSize, subject: face, ratio: ratio, preset: targetPreset, isProfile: item.isProfile)
        guard rect.width > 0, rect.height > 0 else { return }

        let targetFrame = targetFrameSize(for: targetPreset)
        let base = max(targetFrame.width / img.size.width, targetFrame.height / img.size.height)
        let pointsToPixels = CGFloat(cg.width) / img.size.width
        let targetCropWInPoints = rect.width / pointsToPixels
        let targetZoom = max(1.0, min(targetFrame.width / (targetCropWInPoints * base), 4.0))

        let cropCenterInPoints = CGPoint(x: rect.midX / pointsToPixels, y: rect.midY / pointsToPixels)
        let imageCenterInPoints = CGPoint(x: img.size.width / 2, y: img.size.height / 2)

        let requiredOffsetX = (imageCenterInPoints.x - cropCenterInPoints.x) * base * targetZoom
        let requiredOffsetY = (imageCenterInPoints.y - cropCenterInPoints.y) * base * targetZoom

        let applyTransform = {
            zoom = targetZoom
            offset = clampOffset(CGSize(width: requiredOffsetX, height: requiredOffsetY), zoomFactor: targetZoom, customFrame: targetFrame)
            dragOffset = .zero
            pinchScale = 1.0
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                applyTransform()
            }
            Haptics.tick()
        } else {
            applyTransform()
        }
    }

    private func saveCrop() {
        guard let img = originalImage, let cg = img.cgImage else { saveError = true; return }
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
            saveError = true
            return
        }

        let croppedImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
        guard HeadshotStore.replace(croppedImage, key: item.key, auditionID: item.auditionID) else {
            saveError = true
            return
        }
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

// MARK: - 11 Full-Screen Headshot Inspection Sheet

struct HeadshotViewerItem: Identifiable {
    let key: String
    let title: String
    let isProfile: Bool
    var auditionID: UUID? = nil
    var id: String { "view-\(key)-\(auditionID?.uuidString ?? "profile")" }
}

struct HeadshotViewerSheet: View {
    let item: HeadshotViewerItem
    let onAdjust: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var replacePickerItem: PhotosPickerItem?

    private var image: UIImage? {
        HeadshotStore.load(key: item.key, auditionID: item.auditionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(
                title: item.title,
                backLabel: "Done",
                onDark: true,
                onBack: { dismiss() }
            )
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color.black)

            ZStack {
                Color.black.ignoresSafeArea()

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom action bar
            HStack(spacing: 12) {
                // Adjust button
                Button {
                    dismiss()
                    onAdjust()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crop")
                        Text("Adjust & Frame")
                    }
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.accent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Replace menu (Photos or Camera)
                Menu {
                    PhotosPicker(selection: $replacePickerItem, matching: .images) {
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
                    .foregroundStyle(OT.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Remove button
                Button(role: .destructive) {
                    let dir = item.auditionID != nil
                        ? MediaStore.directory("audition_headshots/\(item.auditionID!.uuidString)")
                        : MediaStore.directory("headshots")
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.key).jpg"))
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.key)_original.jpg"))
                    HeadshotStore.clearCache()
                    store.headshotVersion += 1
                    store.syncHeadshotPieces()
                    Haptics.warning()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.danger)
                        .frame(width: 46, height: 46)
                        .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 14)
            .background(OT.surfaceRaised)
        }
        .preferredColorScheme(.dark)
        .onChange(of: replacePickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        HeadshotStore.save(img, key: item.key, auditionID: item.auditionID)
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        Haptics.success()
                        dismiss()
                        onAdjust()
                    }
                }
            }
        }
    }
}
