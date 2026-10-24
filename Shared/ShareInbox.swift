import Foundation

/// Casting notices and sides shared to OneTake from Mail, WhatsApp, Safari, Photos or Files.
///
/// A share extension can't open its app, so the extension drops what it was given into this inbox
/// in the App Group container (both can reach it), and the app picks it up the next time it comes
/// to the foreground, opening Add audition with it. Each share is one folder: `text.txt` for any
/// text, plus the shared images and PDFs as files.
enum ShareInbox {
    struct Item: Hashable {
        let folder: URL
        var text: String?
        var images: [URL]
        var pdfs: [URL]

        var isEmpty: Bool { (text?.isEmpty ?? true) && images.isEmpty && pdfs.isEmpty }
    }

    static let textFileName = "text.txt"

    static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appendingPathComponent("ShareInbox", isDirectory: true)
    }

    /// A fresh folder for one share. Named by time first so the oldest share is picked up first.
    static func makeItemFolder(now: Date = .now) -> URL? {
        guard let root else { return nil }
        let name = "\(Int(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let folder = root.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// The oldest waiting share, if any. Empty leftovers (a share that saved nothing) are cleared.
    static func next() -> Item? {
        guard let root,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return nil }
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let item = read(folder)
            if item.isEmpty { try? FileManager.default.removeItem(at: folder) } else { return item }
        }
        return nil
    }

    static func read(_ folder: URL) -> Item {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let text = try? String(contentsOf: folder.appendingPathComponent(textFileName), encoding: .utf8)
        let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return Item(
            folder: folder,
            text: text?.trimmingCharacters(in: .whitespacesAndNewlines),
            images: sorted.filter { ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif"].contains($0.pathExtension.lowercased()) },
            pdfs: sorted.filter { $0.pathExtension.lowercased() == "pdf" }
        )
    }

    /// Once the app has read a share, it's gone from the inbox.
    static func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.folder)
    }
}
