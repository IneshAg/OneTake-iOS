import Foundation

/// What the widgets and the Live Activity show, written by the app into the shared App Group
/// container and read by the widget extension. Kept small and self-contained: the extension never
/// sees the app's full state.
struct WidgetSnapshot: Codable, Hashable {
    struct Piece: Codable, Hashable {
        enum Status: String, Codable, Hashable { case done, next, todo }
        var title: String
        var status: Status
    }

    struct Item: Codable, Hashable, Identifiable {
        var id: UUID
        var project: String
        var role: String
        var due: Date
        var pieces: [Piece]

        var readyCount: Int { pieces.filter { $0.status == .done }.count }
        var nextTitle: String? { pieces.first { $0.status == .next }?.title }
        /// "2 of 4 · Scene 1 next", or "Ready to send" once everything's in.
        var progressLine: String {
            guard let next = nextTitle else { return "Ready to send" }
            return "\(readyCount) of \(pieces.count) · \(next) next"
        }
        /// Opens this audition in the app.
        var url: URL { URL(string: "onetake://audition/\(id.uuidString)")! }
    }

    /// Unsent auditions, soonest first.
    var upcoming: [Item]

    static let appGroup = "group.com.srmist.onetake"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// "13" + "h" — hours until due under two days, then days. Never negative.
func otTimeLeft(until due: Date, from now: Date = .now) -> (number: String, unit: String) {
    let hours = max(0, Int(due.timeIntervalSince(now) / 3600))
    return hours < 48 ? ("\(hours)", "h") : ("\(hours / 24)", "d")
}
