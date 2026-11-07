import Foundation

struct LocalBackupPayload: Codable {
    var formatVersion: Int = 1
    var createdAt = Date()
    var state: PersistedState
    var settings: BackupSettings
}

struct BackupSettings: Codable {
    var strings: [String: String] = [:]
    var booleans: [String: Bool] = [:]
    var integers: [String: Int] = [:]
    var numbers: [String: Double] = [:]

    private static let stringKeys = ["appearance", "readerVolume"]
    private static let booleanKeys = [
        "camera.gesturesEnabled", "camera.voiceCommandsEnabled", "slateAtStart", "practice.showSample", "prompter.followVoice",
        "prompter.mirror", "camera.poseGuideEnabled", "n.liveActivity", "n.morning", "n.twoHours",
        "n.delivery", "n.practice"
    ]
    private static let integerKeys = ["prompter.size"]
    private static let numberKeys = ["camera.gestureHoldDuration"]

    static func current() -> Self {
        let defaults = UserDefaults.standard
        var settings = Self()
        for key in stringKeys {
            if let value = defaults.string(forKey: key) { settings.strings[key] = value }
        }
        for key in booleanKeys where defaults.object(forKey: key) != nil {
            settings.booleans[key] = defaults.bool(forKey: key)
        }
        for key in integerKeys where defaults.object(forKey: key) != nil {
            settings.integers[key] = defaults.integer(forKey: key)
        }
        for key in numberKeys where defaults.object(forKey: key) != nil {
            settings.numbers[key] = defaults.double(forKey: key)
        }
        return settings
    }

    func apply() {
        let defaults = UserDefaults.standard
        for (key, value) in strings { defaults.set(value, forKey: key) }
        for (key, value) in booleans { defaults.set(value, forKey: key) }
        for (key, value) in integers { defaults.set(value, forKey: key) }
        for (key, value) in numbers { defaults.set(value, forKey: key) }
    }
}

struct LocalBackupFile: Sendable {
    let name: String
    let url: URL
}

struct LocalBackupJob: Sendable {
    let payload: Data
    let files: [LocalBackupFile]
}

enum LocalBackup {
    private static let payloadName = "onetake-backup.json"

    static func prepareExport(from store: AppStore) throws -> LocalBackupJob {
        var state = PersistedState()
        state.auditions = store.auditions
        state.takes = store.takes
        state.practice = store.practice
        state.slate = store.slate
        state.isOnboarded = store.isOnboarded
        // Authentication is device-specific; a data backup never copies sign-in state.
        state.account = nil
        let payload = LocalBackupPayload(state: state, settings: .current())
        let payloadData = try JSONEncoder().encode(payload)
        var files: [LocalBackupFile] = []
        let documents = MediaStore.documentsURL
        if let enumerator = FileManager.default.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let relative = String(fileURL.path.dropFirst(documents.path.count + 1))
                guard !relative.isEmpty else { continue }
                files.append(LocalBackupFile(name: "Documents/\(relative)", url: fileURL))
            }
        }
        return LocalBackupJob(payload: payloadData, files: files)
    }

    static func writeArchive(_ job: LocalBackupJob) throws -> URL {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetake-backup-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let payloadURL = workDirectory.appendingPathComponent(payloadName)
            try job.payload.write(to: payloadURL, options: .atomic)
            let entries = [ZipArchive.Entry(name: payloadName, fileURL: payloadURL)]
                + job.files.map { ZipArchive.Entry(name: $0.name, fileURL: $0.url) }
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let archiveURL = workDirectory.appendingPathComponent("OneTake-Backup-\(stamp).zip")
            try ZipArchive.write(entries, to: archiveURL)
            return archiveURL
        } catch {
            try? FileManager.default.removeItem(at: workDirectory)
            throw error
        }
    }

    static func extract(from archiveURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ZipArchive.ArchiveError.invalid("Backup archive not found at \(archiveURL.path)")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetake-restore-\(UUID().uuidString)", isDirectory: true)
        do {
            try ZipArchive.extract(from: archiveURL, to: directory)
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func readPayload(in directory: URL) throws -> LocalBackupPayload {
        let payloadURL = directory.appendingPathComponent(payloadName)
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw ZipArchive.ArchiveError.invalid("Backup manifest is missing (\(payloadName) not found)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: payloadURL)
        } catch {
            throw ZipArchive.ArchiveError.invalid("Failed to read backup manifest: \(error.localizedDescription)")
        }
        let payload: LocalBackupPayload
        do {
            payload = try JSONDecoder().decode(LocalBackupPayload.self, from: data)
        } catch {
            throw ZipArchive.ArchiveError.invalid("Corrupted backup manifest: \(error.localizedDescription)")
        }
        guard payload.formatVersion == 1 else {
            throw ZipArchive.ArchiveError.invalid("Unsupported backup format version (\(payload.formatVersion))")
        }
        guard payload.state.droppedRecords == 0 else {
            throw ZipArchive.ArchiveError.invalid("Backup contains unreadable or corrupted audition records")
        }
        let documents = directory.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return payload
    }

    static func discardStaging(_ directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Durable Restore Journal & State Machine (AUDIT-FINDING-02)

    /// Snapshot entry capturing original Documents directory items before any destructive operations.
    struct OriginalEntrySnapshot: Codable, Equatable {
        var name: String
        var isDirectory: Bool
    }

    /// Persistent journal recorded outside tmp in Application Support before any live modification,
    /// enabling deterministic, idempotent recovery if the app terminates or power is lost during restore.
    struct RestoreJournal: Codable {
        var formatVersion: Int = 1
        var operationID: UUID
        var state: RestoreState
        var stagedDirectoryPath: String
        var rollbackDirectoryPath: String
        var destinationDirectoryPath: String
        var originalSnapshot: [OriginalEntrySnapshot] = []
        var originalItemsMoved: [String] = []
        var incomingItemsInstalled: [String] = []
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        enum RestoreState: String, Codable {
            case prepared
            case preservationStarted
            case preservationCompleted
            case installationStarted
            case installationCompleted
            case validationCompleted
            case committed
        }

        enum CodingKeys: String, CodingKey {
            case formatVersion, operationID, state, stagedDirectoryPath, rollbackDirectoryPath, destinationDirectoryPath
            case originalSnapshot, originalItemsMoved, incomingItemsInstalled, createdAt, updatedAt
        }

        init(
            operationID: UUID,
            state: RestoreState,
            stagedDirectoryPath: String,
            rollbackDirectoryPath: String,
            destinationDirectoryPath: String,
            originalSnapshot: [OriginalEntrySnapshot] = [],
            originalItemsMoved: [String] = [],
            incomingItemsInstalled: [String] = []
        ) {
            self.formatVersion = 1
            self.operationID = operationID
            self.state = state
            self.stagedDirectoryPath = stagedDirectoryPath
            self.rollbackDirectoryPath = rollbackDirectoryPath
            self.destinationDirectoryPath = destinationDirectoryPath
            self.originalSnapshot = originalSnapshot
            self.originalItemsMoved = originalItemsMoved
            self.incomingItemsInstalled = incomingItemsInstalled
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
            operationID = try container.decode(UUID.self, forKey: .operationID)
            state = try container.decode(RestoreState.self, forKey: .state)
            stagedDirectoryPath = try container.decode(String.self, forKey: .stagedDirectoryPath)
            rollbackDirectoryPath = try container.decode(String.self, forKey: .rollbackDirectoryPath)
            destinationDirectoryPath = try container.decode(String.self, forKey: .destinationDirectoryPath)
            originalSnapshot = try container.decodeIfPresent([OriginalEntrySnapshot].self, forKey: .originalSnapshot) ?? []
            originalItemsMoved = try container.decodeIfPresent([String].self, forKey: .originalItemsMoved) ?? []
            incomingItemsInstalled = try container.decodeIfPresent([String].self, forKey: .incomingItemsInstalled) ?? []
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        }
    }

    static var appSupportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneTake", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var journalURL: URL {
        appSupportDirectory.appendingPathComponent("restore-journal.json")
    }

    static func rollbackDirectory(for operationID: UUID) -> URL {
        appSupportDirectory.appendingPathComponent("RestoreRollback", isDirectory: true)
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
    }

    static func writeJournal(_ journal: RestoreJournal) throws {
        var j = journal
        j.updatedAt = Date()
        let data = try JSONEncoder().encode(j)
        try data.write(to: journalURL, options: .atomic)
    }

    static func removeJournal() {
        try? FileManager.default.removeItem(at: journalURL)
    }

    private static func isSafeSandboxPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("..") else { return false }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let allowedRoots = [
            MediaStore.documentsURL.standardizedFileURL.path,
            appSupportDirectory.standardizedFileURL.path,
            FileManager.default.temporaryDirectory.standardizedFileURL.path
        ]
        return allowedRoots.contains { root in
            url.path == root || url.path.hasPrefix(root + "/")
        }
    }

    /// Checks for an interrupted restore operation and deterministically recovers the environment
    /// before any app subsystem accesses restored data. Idempotent and crash-consistent.
    @discardableResult
    static func recoverUnfinishedRestoreIfNeeded() throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: journalURL.path) else { return false }
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(RestoreJournal.self, from: data) else {
            // Corrupt journal: preserve rollback folder for safety, archive damaged journal
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            try? manager.moveItem(at: journalURL, to: appSupportDirectory.appendingPathComponent("restore-journal-corrupt-\(stamp).json"))
            return false
        }

        // Path traversal defense: verify referenced directories are strictly app-owned
        guard isSafeSandboxPath(journal.destinationDirectoryPath),
              isSafeSandboxPath(journal.rollbackDirectoryPath) else {
            throw ZipArchive.ArchiveError.invalid("Restore journal references unsafe paths")
        }

        let destination = URL(fileURLWithPath: journal.destinationDirectoryPath, isDirectory: true)
        let rollbackDir = URL(fileURLWithPath: journal.rollbackDirectoryPath, isDirectory: true)

        if journal.state == .committed {
            // Validation & commit completed before termination: finish cleanup
            if manager.fileExists(atPath: rollbackDir.path) {
                try? manager.removeItem(at: rollbackDir)
            }
            removeJournal()
            return true
        }

        // Interrupted before commit: roll back to original data deterministically
        let originalSnapshotNames = Set(journal.originalSnapshot.map(\.name))
        let rollbackContents = (try? manager.contentsOfDirectory(at: rollbackDir, includingPropertiesForKeys: nil)) ?? []
        let rollbackNames = Set(rollbackContents.map(\.lastPathComponent))

        // Step 1: Reconcile destination (Documents) directory against the original snapshot and rollback contents.
        // Remove only entries that are provably introduced by the interrupted restore.
        let currentDestContents = (try? manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        for itemURL in currentDestContents {
            let itemName = itemURL.lastPathComponent
            if rollbackNames.contains(itemName) {
                // An original copy is safely preserved in rollback storage.
                // The item currently in destination is an incoming file that overwrote the original (or a duplicate).
                // Safely remove it from destination so the original can be restored.
                try? manager.removeItem(at: itemURL)
            } else if originalSnapshotNames.contains(itemName) {
                // This item was present originally and was never moved to rollback (e.g. crash during preservation).
                // It is original user data that must be preserved!
                continue
            } else {
                // Item is NOT in rollback storage AND was NOT in the original snapshot.
                // This entry is provably introduced by the restore (e.g. incoming file copied into Documents,
                // even if the crash occurred before the journal recorded it in incomingItemsInstalled).
                try? manager.removeItem(at: itemURL)
            }
        }

        // Also clean up any recorded installed items that might remain
        for installedItem in journal.incomingItemsInstalled {
            let itemURL = destination.appendingPathComponent(installedItem)
            if manager.fileExists(atPath: itemURL.path) {
                try? manager.removeItem(at: itemURL)
            }
        }

        // Step 2: Restore all original items from rollback directory
        for rollbackItem in rollbackContents {
            let targetURL = destination.appendingPathComponent(rollbackItem.lastPathComponent)
            if manager.fileExists(atPath: targetURL.path) {
                try? manager.removeItem(at: targetURL)
            }
            try manager.moveItem(at: rollbackItem, to: targetURL)
        }

        // Step 3: Verify the restored original state against the original snapshot
        for expected in journal.originalSnapshot {
            let expectedURL = destination.appendingPathComponent(expected.name)
            guard manager.fileExists(atPath: expectedURL.path) else {
                // Original file could not be restored! Do NOT delete rollback data or journal!
                throw ZipArchive.ArchiveError.invalid("Restore rollback verification failed: original entry '\(expected.name)' is missing")
            }
        }

        // Step 4: Verification passed: remove rollback directory and delete journal
        if manager.fileExists(atPath: rollbackDir.path) {
            try? manager.removeItem(at: rollbackDir)
        }
        removeJournal()
        return true
    }

    /// Safely replaces the contents of the application's root Documents directory with durable
    /// crash-recovery journaling outside tmp, preserving the root Documents container inode.
    static func replaceDocuments(with stagedDirectory: URL) throws {
        do {
            try executeReplaceDocuments(with: stagedDirectory)
        } catch {
            _ = try? recoverUnfinishedRestoreIfNeeded()
            throw error
        }
    }

    private static func executeReplaceDocuments(with stagedDirectory: URL) throws {
        let manager = FileManager.default
        let destination = MediaStore.documentsURL
        
        // 1. Pre-flight validation before touching any live data
        guard manager.fileExists(atPath: destination.path) else {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        let source = stagedDirectory.appendingPathComponent("Documents", isDirectory: true)
        guard manager.fileExists(atPath: source.path) else {
            throw ZipArchive.ArchiveError.invalid("Staged backup Documents directory missing")
        }

        // 2. Prepare durable rollback directory outside tmp in Application Support
        let operationID = UUID()
        let rollbackDir = rollbackDirectory(for: operationID)
        try manager.createDirectory(at: rollbackDir, withIntermediateDirectories: true)

        // Capture complete durable snapshot of original Documents entries BEFORE touching any files
        let existingContents = (try? manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        let originalSnapshot: [OriginalEntrySnapshot] = existingContents.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return OriginalEntrySnapshot(name: url.lastPathComponent, isDirectory: isDir)
        }

        var journal = RestoreJournal(
            operationID: operationID,
            state: .prepared,
            stagedDirectoryPath: stagedDirectory.path,
            rollbackDirectoryPath: rollbackDir.path,
            destinationDirectoryPath: destination.path,
            originalSnapshot: originalSnapshot
        )
        try writeJournal(journal)

        // 3. Move existing live items from Documents into rollback directory
        journal.state = .preservationStarted
        try writeJournal(journal)

        let existingItems = (try? manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        for item in existingItems {
            let rollbackTarget = rollbackDir.appendingPathComponent(item.lastPathComponent)
            try manager.moveItem(at: item, to: rollbackTarget)
            journal.originalItemsMoved.append(item.lastPathComponent)
            try writeJournal(journal)
        }

        journal.state = .preservationCompleted
        try writeJournal(journal)

        // 4. Copy new staged items into destination (root Documents)
        journal.state = .installationStarted
        try writeJournal(journal)

        let newItems = (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for item in newItems {
            let destTarget = destination.appendingPathComponent(item.lastPathComponent)
            if manager.fileExists(atPath: destTarget.path) {
                try manager.removeItem(at: destTarget)
            }
            try manager.copyItem(at: item, to: destTarget)
            journal.incomingItemsInstalled.append(item.lastPathComponent)
            try writeJournal(journal)
        }

        journal.state = .installationCompleted
        try writeJournal(journal)

        // 5. Post-install validation
        guard manager.fileExists(atPath: destination.path) else {
            throw ZipArchive.ArchiveError.invalid("Destination directory missing after install")
        }
        journal.state = .validationCompleted
        try writeJournal(journal)

        // 6. Commit
        journal.state = .committed
        try writeJournal(journal)

        // 7. Cleanup
        try? manager.removeItem(at: rollbackDir)
        removeJournal()
    }

    static func discardArchive(_ archiveURL: URL?) {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
    }
}
