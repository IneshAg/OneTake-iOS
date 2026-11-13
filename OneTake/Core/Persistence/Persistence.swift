import Foundation
import UIKit

// MARK: - App state persistence (JSON on disk, no backend — matches "nothing leaves this iPhone")

/// Everything AppStore needs to survive a relaunch. Media files themselves live under `MediaStore`;
/// this only holds the structured data (and the URLs pointing at those files).
struct PersistedState: Codable {
    var auditions: [Audition] = []
    var takes: [Take] = []
    var practice: [PracticePiece] = []
    var slate = SlateInfo()
    var isOnboarded = false
    /// Optional, so state saved before accounts existed still loads (an old `isSignedIn` flag is
    /// simply ignored — it never had a real account behind it).
    var account: Account?
    /// How many saved records couldn't be read back and were left out. Never written to disk.
    var droppedRecords = 0

    private enum CodingKeys: String, CodingKey {
        case auditions, takes, practice, slate, isOnboarded, account
    }
}

// In an extension so the memberwise initializer AppStore uses survives.
extension PersistedState {
    /// Reads each audition, take and practice piece on its own: one record that no longer decodes
    /// (a damaged file, or a field a newer version renamed) is left out instead of taking every other
    /// record — and the onboarding flag — down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var dropped = 0
        func records<T: Decodable>(_ key: CodingKeys) -> [T] {
            guard let all = try? c.decodeIfPresent([Lossy<T>].self, forKey: key) else {
                if c.contains(key) { dropped += 1 }
                return []
            }
            dropped += all.filter { $0.value == nil }.count
            return all.compactMap(\.value)
        }
        auditions = records(.auditions)
        takes = records(.takes)
        practice = records(.practice)
        slate = (try? c.decodeIfPresent(SlateInfo.self, forKey: .slate)) ?? SlateInfo()
        isOnboarded = (try? c.decodeIfPresent(Bool.self, forKey: .isOnboarded)) ?? false
        account = try? c.decodeIfPresent(Account.self, forKey: .account)
        droppedRecords = dropped
    }
}

/// One array element that may fail to decode; the failure is kept as nil so the rest still load.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum Persistence {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneTake", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { directory.appendingPathComponent("state.json") }

    static func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return decode(data, keepingUnreadable: keepUnreadableCopy)
    }

    /// Decodes saved state. Whenever any of it can't be read, `keepingUnreadable` gets the original
    /// bytes first — the next save replaces state.json, and that must never be the only copy.
    static func decode(_ data: Data, keepingUnreadable: (Data) -> Void) -> PersistedState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let string = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported date format: \(string)")
        }
        guard let state = try? decoder.decode(PersistedState.self, from: data) else {
            keepingUnreadable(data)
            return nil
        }
        if state.droppedRecords > 0 { keepingUnreadable(data) }
        return state
    }

    private static func keepUnreadableCopy(_ data: Data) {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: directory.appendingPathComponent("state-unreadable-\(stamp).json"), options: .atomic)
    }

    static func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Media files (recorded takes, slate/full-length clips, exports) — Documents, not temp

/// Moves real recordings out of the temporary directory `CameraController` records into, so they
/// survive past the recording session instead of being purged by the system.
enum MediaStore {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// iOS can move the app's container between installs, updates and restores, so a persisted absolute
    /// file URL may point at a container that no longer exists. Re-anchors anything stored under
    /// Documents onto the current Documents directory; leaves other URLs untouched.
    static func rebased(_ url: URL?) -> URL? {
        guard let url, url.isFileURL else { return url }
        guard let range = url.path.range(of: "/Documents/") else { return url }
        return documentsURL.appendingPathComponent(String(url.path[range.upperBound...]))
    }

    static func directory(_ subfolder: String) -> URL {
        let dir = documentsURL.appendingPathComponent(subfolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Moves a just-recorded temp file to permanent on-disk storage.
    /// If a file already exists at the destination, it is safely backed up during the move so a
    /// failed save never destroys the superseded recording.
    /// Returns nil (rather than a bogus URL) if there was nothing real to persist — e.g. the Simulator,
    /// which has no camera and never produces a `lastRecording`.
    @discardableResult
    static func persist(_ tempURL: URL?, as name: String, in subfolder: String) -> URL? {
        guard let tempURL, FileManager.default.fileExists(atPath: tempURL.path) else { return nil }
        let dir = directory(subfolder)
        let dest = dir.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: dest.path) {
            let backupName = "backup-\(UUID().uuidString)-\(name)"
            let backup = dir.appendingPathComponent(backupName)
            do {
                try FileManager.default.moveItem(at: dest, to: backup)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    try? FileManager.default.removeItem(at: backup)
                    return dest
                } catch {
                    // Restore previous file if new recording move fails
                    try? FileManager.default.moveItem(at: backup, to: dest)
                    return nil
                }
            } catch {
                return nil
            }
        } else {
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                return dest
            } catch {
                return nil
            }
        }
    }

    /// Total bytes under a subfolder — used by Privacy & data instead of guessing.
    static func sizeOnDisk(_ subfolder: String) -> Int64 {
        let dir = documentsURL.appendingPathComponent(subfolder, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
        }
        return total
    }

    static func deleteAll(_ subfolders: [String]) {
        for folder in subfolders {
            try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(folder, isDirectory: true))
        }
    }
}

enum ResumeStore {
    /// Copies a resume selected through the Files picker into durable, app-owned storage.
    /// The picker URL can be security-scoped and may stop being available after the import ends.
    static func importFile(from sourceURL: URL) throws -> URL {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        guard ["pdf", "doc", "docx", "rtf", "txt"].contains(ext) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: sourceURL.path])
        }
        let directory = MediaStore.directory("Profile")
        // Keep previous copies intact: older auditions may still reference their submitted résumé.
        let destination = directory
            .appendingPathComponent("Actor-Resume-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

// MARK: - Headshots (real captured photos, keyed by angle)

enum HeadshotStore {

    /// Headshots are drawn in list rows that re-render often; decoding the JPEG from disk every time
    /// made scrolling the auditions list do file I/O per card.
    private static let cache = NSCache<NSString, UIImage>()

    private static func cacheKey(key: String, auditionID: UUID?) -> NSString {
        if let auditionID {
            return "\(auditionID.uuidString)_\(key.lowercased())" as NSString
        } else {
            return "profile_\(key.lowercased())" as NSString
        }
    }

    private static func directory(for auditionID: UUID?) -> URL {
        if let auditionID {
            return MediaStore.directory("audition_headshots/\(auditionID.uuidString)")
        } else {
            return MediaStore.directory("headshots")
        }
    }

    private static func url(for key: String, auditionID: UUID? = nil) -> URL {
        directory(for: auditionID).appendingPathComponent("\(key.lowercased()).jpg")
    }

    /// The untouched capture, kept the first time a photo is reframed so every later reframe starts
    /// from the full original instead of cropping an already-cropped photo (which kept zooming in).
    private static func originalURL(for key: String, auditionID: UUID? = nil) -> URL {
        directory(for: auditionID).appendingPathComponent("\(key.lowercased())_original.jpg")
    }

    /// A fresh capture. Drops any original kept from a previous reframe — it belongs to the old photo.
    static func save(_ image: UIImage, key: String, auditionID: UUID? = nil) {
        try? FileManager.default.removeItem(at: originalURL(for: key, auditionID: auditionID))
        write(image, key: key, auditionID: auditionID)
    }

    /// An edit of the current photo (e.g. auto-framing). Keeps the original capture on the first edit.
    @discardableResult
    static func replace(_ image: UIImage, key: String, auditionID: UUID? = nil) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return false }
        let original = originalURL(for: key, auditionID: auditionID)
        let mainURL = url(for: key, auditionID: auditionID)
        if !FileManager.default.fileExists(atPath: original.path), exists(key: key, auditionID: auditionID) {
            try? FileManager.default.copyItem(at: mainURL, to: original)
        }
        do {
            try data.write(to: mainURL, options: .atomic)
        } catch {
            return false
        }
        cache.setObject(image, forKey: cacheKey(key: key, auditionID: auditionID))
        return true
    }

    /// The full original capture if the photo has been reframed, otherwise the current photo.
    static func loadOriginal(key: String, auditionID: UUID? = nil) -> UIImage? {
        UIImage(contentsOfFile: originalURL(for: key, auditionID: auditionID).path) ?? load(key: key, auditionID: auditionID)
    }

    private static func write(_ image: UIImage, key: String, auditionID: UUID? = nil) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let target = url(for: key, auditionID: auditionID)
        try? data.write(to: target, options: .atomic)
        cache.setObject(image, forKey: cacheKey(key: key, auditionID: auditionID))
    }

    static func load(key: String, auditionID: UUID? = nil) -> UIImage? {
        let cKey = cacheKey(key: key, auditionID: auditionID)
        if let cached = cache.object(forKey: cKey) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: key, auditionID: auditionID).path) else { return nil }
        cache.setObject(image, forKey: cKey)
        return image
    }

    static func exists(key: String, auditionID: UUID? = nil) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key, auditionID: auditionID).path)
    }

    /// The audition headshots that have been taken, in order: front, then left and right profiles.
    static let angles: [(key: String, title: String)] = [("front", "Front"), ("left", "Left profile"), ("right", "Right profile")]

    /// Formatted requirement summary (e.g. "3 photos (front, left, right profile)").
    static var requirementDescription: String {
        let names = angles.map { $0.key == "front" ? "front" : ($0.key == "left" ? "left" : $0.title.lowercased()) }
        return "\(angles.count) photos (\(names.joined(separator: ", ")))"
    }

    /// Whether all required angle headshots (front, left, right profile) are present.
    static func isComplete(auditionID: UUID? = nil) -> Bool {
        angles.allSatisfy { exists(key: $0.key, auditionID: auditionID) }
    }

    static func taken(auditionID: UUID? = nil) -> [(key: String, title: String)] {
        angles.filter { exists(key: $0.key, auditionID: auditionID) }
    }

    /// Backwards compatible property for default profile headshots.
    static var taken: [(key: String, title: String)] {
        taken(auditionID: nil)
    }

    /// Call after deleting the headshots folder so stale images aren't drawn from memory.
    static func clearCache() { cache.removeAllObjects() }

    /// Copies the default profile headshots to an audition so the audition has its own frozen copy.
    static func copyProfileHeadshots(to auditionID: UUID) {
        let profileDir = directory(for: nil)
        let auditionDir = directory(for: auditionID)
        for angle in angles {
            let src = profileDir.appendingPathComponent("\(angle.key).jpg")
            let dst = auditionDir.appendingPathComponent("\(angle.key).jpg")
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
            let srcOrig = profileDir.appendingPathComponent("\(angle.key)_original.jpg")
            let dstOrig = auditionDir.appendingPathComponent("\(angle.key)_original.jpg")
            if FileManager.default.fileExists(atPath: srcOrig.path) {
                try? FileManager.default.removeItem(at: dstOrig)
                try? FileManager.default.copyItem(at: srcOrig, to: dstOrig)
            }
        }
        clearCache()
    }

    /// Removes a specific angle photo and its original backup.
    static func remove(key: String, auditionID: UUID? = nil) {
        let fm = FileManager.default
        try? fm.removeItem(at: url(for: key, auditionID: auditionID))
        try? fm.removeItem(at: originalURL(for: key, auditionID: auditionID))
        cache.removeObject(forKey: cacheKey(key: key, auditionID: auditionID))
    }

    /// Removes all headshots attached to a specific audition.
    static func removeAuditionHeadshots(for auditionID: UUID) {
        let auditionDir = directory(for: auditionID)
        try? FileManager.default.removeItem(at: auditionDir)
        clearCache()
    }

    /// Copies of the taken headshots named to match the tape (LAST_FIRST_ROLE_PROJECT_HEADSHOT_FRONT.jpg),
    /// to send alongside it as photos.
    static func deliverables(baseName: String, auditionID: UUID? = nil) -> [URL] {
        let dir = MediaStore.directory("Exports")
        return taken(auditionID: auditionID).compactMap { angle in
            let dest = dir.appendingPathComponent("\(baseName)_HEADSHOT_\(angle.key.uppercased()).jpg")
            try? FileManager.default.removeItem(at: dest)
            return (try? FileManager.default.copyItem(at: url(for: angle.key, auditionID: auditionID), to: dest)) != nil ? dest : nil
        }
    }
}
