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
    var isSignedIn = false
}

enum Persistence {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneTake", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
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

    /// Moves a just-recorded temp file to permanent on-disk storage, replacing anything already there.
    /// Returns nil (rather than a bogus URL) if there was nothing real to persist — e.g. the Simulator,
    /// which has no camera and never produces a `lastRecording`.
    @discardableResult
    static func persist(_ tempURL: URL?, as name: String, in subfolder: String) -> URL? {
        guard let tempURL, FileManager.default.fileExists(atPath: tempURL.path) else { return nil }
        let dest = directory(subfolder).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            return nil
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

// MARK: - Headshots (real captured photos, keyed by angle)

enum HeadshotStore {
    private static func url(for key: String) -> URL {
        MediaStore.directory("headshots").appendingPathComponent("\(key.lowercased()).jpg")
    }

    static func save(_ image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    static func load(key: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: key).path)
    }

    static func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }
}
