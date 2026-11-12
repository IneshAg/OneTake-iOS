import Foundation

// MARK: - Takes

struct Take: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: Int
    var duration: TimeInterval
    var recordedAt: Date
    var isCircled: Bool
    var notes: [String]
    var fileURL: URL?
    /// Kept separately after trimming so the actor can restore the recorded source clip.
    var originalFileURL: URL? = nil
    /// Which audition/scene this take belongs to. Real takes created by `ShootFlow` always set
    /// both; optional only so `Take` can still be constructed in previews/tests without one.
    var auditionID: Audition.ID?
    var sceneIndex: Int?
    var isPreviousSides: Bool? = false
    var previousSides: Bool { isPreviousSides ?? false }
    var previousSidesLabel: String? = nil
    var sidesRevision: Int? = 0
    var currentSidesRevision: Int { sidesRevision ?? 0 }
}

// MARK: - Tape check

struct TapeFinding: Identifiable, Hashable {
    var id = UUID()
    var category: String
    var title: String
    var where_: String
    var advice: String
    /// The clip and moment this is about, so Tape Check can play exactly that moment.
    var clipURL: URL? = nil
    var seconds: Double? = nil
    /// True for heuristic timing cues that may be intentional, such as a pause or immediate start.
    var isSoftPrompt: Bool = false
}
