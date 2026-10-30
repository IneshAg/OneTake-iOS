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
        "camera.gesturesEnabled", "slateAtStart", "practice.showSample", "prompter.followVoice",
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
        let payload = try JSONDecoder().decode(LocalBackupPayload.self, from: Data(contentsOf: payloadURL))
        guard payload.formatVersion == 1, payload.state.droppedRecords == 0 else {
            throw ZipArchive.ArchiveError.invalid("unsupported version or unreadable records")
        }
        let documents = directory.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return payload
    }

    static func discardStaging(_ directory: URL?) {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    static func replaceDocuments(with stagedDirectory: URL) throws {
        let manager = FileManager.default
        let destination = MediaStore.documentsURL
        let parent = destination.deletingLastPathComponent()
        let replacement = parent.appendingPathComponent(".onetake-documents-new-\(UUID().uuidString)", isDirectory: true)
        let previous = parent.appendingPathComponent(".onetake-documents-old-\(UUID().uuidString)", isDirectory: true)
        let source = stagedDirectory.appendingPathComponent("Documents", isDirectory: true)

        try manager.copyItem(at: source, to: replacement)
        let hadCurrent = manager.fileExists(atPath: destination.path)
        if hadCurrent { try manager.moveItem(at: destination, to: previous) }
        do {
            try manager.moveItem(at: replacement, to: destination)
            if hadCurrent { try? manager.removeItem(at: previous) }
        } catch {
            if hadCurrent, !manager.fileExists(atPath: destination.path) {
                try? manager.moveItem(at: previous, to: destination)
            }
            try? manager.removeItem(at: replacement)
            throw error
        }
    }

    static func discardArchive(_ archiveURL: URL?) {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
    }
}
