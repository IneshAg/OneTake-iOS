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

    /// Safely replaces the contents of the application's root Documents directory without ever
    /// renaming, unlinking, or moving the root container directory itself (preventing iOS sandbox violations).
    /// Preserves a full rollback copy in isolated temporary storage, ensuring that any failure or interruption
    /// cleanly rolls back to the previous data state.
    static func replaceDocuments(with stagedDirectory: URL) throws {
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

        // 2. Prepare isolated rollback staging directory in temporary space
        let rollbackDir = manager.temporaryDirectory
            .appendingPathComponent("onetake-restore-rollback-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: rollbackDir, withIntermediateDirectories: true)

        // 3. Move existing live items from Documents into rollback directory (preserving root Documents container)
        let existingItems = (try? manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        var movedToRollback: [URL] = []
        
        do {
            for item in existingItems {
                let rollbackTarget = rollbackDir.appendingPathComponent(item.lastPathComponent)
                try manager.moveItem(at: item, to: rollbackTarget)
                movedToRollback.append(rollbackTarget)
            }
        } catch {
            // Revert any items already moved to rollback back to destination
            for rollbackItem in movedToRollback {
                let restoreTarget = destination.appendingPathComponent(rollbackItem.lastPathComponent)
                try? manager.moveItem(at: rollbackItem, to: restoreTarget)
            }
            try? manager.removeItem(at: rollbackDir)
            throw error
        }

        // 4. Copy new staged items into destination (root Documents)
        let newItems = (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        var copiedToDestination: [URL] = []

        do {
            for item in newItems {
                let destTarget = destination.appendingPathComponent(item.lastPathComponent)
                if manager.fileExists(atPath: destTarget.path) {
                    try manager.removeItem(at: destTarget)
                }
                try manager.copyItem(at: item, to: destTarget)
                copiedToDestination.append(destTarget)
            }
            // 5. Success: safely discard rollback directory
            try? manager.removeItem(at: rollbackDir)
        } catch {
            // 6. Rollback on failure: remove partially copied items and restore original items from rollback directory
            for copiedItem in copiedToDestination {
                try? manager.removeItem(at: copiedItem)
            }
            for rollbackItem in movedToRollback {
                let originalDest = destination.appendingPathComponent(rollbackItem.lastPathComponent)
                if manager.fileExists(atPath: originalDest.path) {
                    try? manager.removeItem(at: originalDest)
                }
                try? manager.moveItem(at: rollbackItem, to: originalDest)
            }
            try? manager.removeItem(at: rollbackDir)
            throw error
        }
    }

    static func discardArchive(_ archiveURL: URL?) {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
    }
}
