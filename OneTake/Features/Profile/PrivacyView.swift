import SwiftUI

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
    private var legacyReaderFiles: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path)) ?? []
        return entries.filter { $0.hasPrefix("reader-line-") }.map { MediaStore.documentsURL.appendingPathComponent($0) }
    }
    private var totalSize: Int64 { rawTakesSize + exportsSize + headshotsSize + readerSize }

    private func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    var body: some View {
        OTScreen(title: "Privacy & data", onBack: { store.pop() }, scrolls: false, insetContent: false) {
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
            VStack(alignment: .leading, spacing: OTSpace.s) {
                HStack(spacing: OTSpace.s) {
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
            .padding(.vertical, OTSpace.xxs)
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
                HStack(spacing: OTSpace.s) {
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

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OTScreen(title: "Privacy policy", onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                section("Private by design", "OneTake has no ads, analytics or tracking. Your work stays on this iPhone unless you share it.")
                section("Signing in", "An account is optional. Sign in only to send a tape as an iCloud link.")
                section("On-device data", "Auditions, sides, takes, slate, headshots and practice are stored on this iPhone and included in its backups.")
                section("Reading sides", "Photos, scans and PDFs are read on-device with Apple Vision and PDFKit.")
                section("Speech recognition", "Voice commands use on-device recognition when available. Otherwise Apple may process speech under its privacy policy.")
                section("Sharing", "A tape leaves this iPhone only when you share it. iCloud links can be downloaded until they expire.")
                section("Reminders and widgets", "These use audition details stored on this iPhone.")
                section("Deleting data", "Clean local data in Profile → Privacy & data. Takes, headshots, reader tracks, and practice pieces are removed from this iPhone. Previously shared iCloud links remain in your iCloud Drive.")
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
            Text(body).font(.otCallout).foregroundStyle(OT.labelSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
