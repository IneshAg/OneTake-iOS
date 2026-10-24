import ActivityKit
import Foundation

/// Live Activity for the audition that's due next: a countdown on the Lock Screen and in the
/// Dynamic Island, which switches to upload progress while its tape is being sent as a link.
struct AuditionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var pieces: [WidgetSnapshot.Piece]
        /// 0…1 while the tape is exporting/uploading; nil otherwise.
        var uploadProgress: Double?

        var readyCount: Int { pieces.filter { $0.status == .done }.count }
        var nextTitle: String? { pieces.first { $0.status == .next }?.title }
        var progressLine: String {
            guard let next = nextTitle else { return "Ready to send" }
            return "\(readyCount) of \(pieces.count) ready · \(next) next"
        }
    }

    var auditionID: UUID
    var project: String
    var role: String
    var due: Date

    var url: URL { URL(string: "onetake://audition/\(auditionID.uuidString)")! }
}
