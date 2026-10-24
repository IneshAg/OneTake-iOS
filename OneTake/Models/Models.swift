import Foundation

// MARK: - Audition

enum PieceKind: String, Codable, CaseIterable, Hashable {
    case headshot, slate, fullLength, scene

    var symbol: String {
        switch self {
        case .headshot:   "person.crop.square"
        case .slate:      "person.text.rectangle"
        case .fullLength: "figure.stand"
        case .scene:      "film"
        }
    }
}

struct Piece: Identifiable, Hashable, Codable {
    var id = UUID()
    var kind: PieceKind
    var title: String
    var detail: String
    var isDone: Bool
}

struct ScriptLine: Identifiable, Hashable, Codable {
    var id = UUID()
    var character: String
    var text: String
    var isMine: Bool
}

struct ScriptScene: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: Int
    var title: String
    var heading: String
    var lines: [ScriptLine]
    var estimatedSeconds: Int
}

enum AuditionStatus: String, Codable, Hashable {
    case due, ready, sent
}

enum Destination: String, Codable, CaseIterable, Hashable, Identifiable {
    case actorsAccess = "Actors Access"
    case castingNetworks = "Casting Networks"
    case spotlight = "Spotlight"
    case emailOrLink = "Email or link"
    var id: String { rawValue }
    var spec: String {
        switch self {
        case .actorsAccess:    "H.264 .mp4 · 1080p · under 500 MB"
        case .castingNetworks: "H.264 .mp4 · 1080p · up to 300 MB"
        case .spotlight:       "H.264 .mp4 · 1080p"
        case .emailOrLink:     "Download link · needs Apple or Google sign-in"
        }
    }

    /// The largest file the site accepts, where it publishes one. It applies to each file sent, and
    /// is counted in decimal megabytes so it stays under the limit whichever way the site counts.
    var maxFileBytes: Int64? {
        switch self {
        case .actorsAccess:    500_000_000
        case .castingNetworks: 300_000_000
        case .spotlight, .emailOrLink: nil
        }
    }

    /// Actors Access asks for the slate and each scene as separate files unless casting says otherwise.
    var prefersSeparateFiles: Bool { self == .actorsAccess }
}

struct Audition: Identifiable, Hashable, Codable {
    var id = UUID()
    var project: String
    var projectType: String
    var role: String
    var roleSize: String
    var castingOffice: String
    var due: Date
    var asks: [String]
    var pieces: [Piece]
    var scenes: [ScriptScene]
    var destination: Destination
    var status: AuditionStatus
    var sentDate: Date?
    var headshotAsset: String = "Headshot"

    /// Real recordings, once this audition has actually been shot — nil until then. Persisted as
    /// file URLs; the files themselves live under `MediaStore`.
    var slateVideoURL: URL?
    var fullLengthVideoURL: URL?
    /// The packaged deliverable, once `MediaExporter` has actually composed one.
    var exportedFileURL: URL?
    /// When the tape went out as separate files instead: slate, full length and each scene, in tape
    /// order. `exportedFileURL` is nil then. Optional (like the two below) so older state decodes.
    var exportedPieceURLs: [URL]?
    /// One file per piece instead of one joined tape. nil means whatever the destination asks for.
    var separateFiles: Bool?
    /// Set (e.g. "720p") when the last export had to come down from full quality to fit the site's limit.
    var exportReducedTo: String?
    /// The iCloud download link sent for "Email or link", and when iCloud stops serving it.
    var shareLink: URL?
    var shareLinkExpires: Date?
    /// Callback round (nil = the first audition) and casting's adjustment notes for it. Optional so
    /// state saved before these existed still decodes.
    var round: Int?
    var castingNotes: String?

    /// "22 days" style remaining lifetime of the sent link, or nil if there's no (live) link.
    var shareLinkTimeLeft: String? {
        guard shareLink != nil, let expires = shareLinkExpires else { return nil }
        let days = Int(ceil(expires.timeIntervalSinceNow / 86400))
        return days > 0 ? "\(days) day\(days == 1 ? "" : "s")" : nil
    }

    /// A link is always one file; the casting sites can take either.
    var sendsSeparateFiles: Bool {
        destination != .emailOrLink && (separateFiles ?? destination.prefersSeparateFiles)
    }

    /// Every file the last export made, in tape order.
    var exportedFiles: [URL] { exportedPieceURLs ?? exportedFileURL.map { [$0] } ?? [] }

    var readyCount: Int { pieces.filter(\.isDone).count }
    var totalCount: Int { pieces.count }
    var nextPiece: Piece? { pieces.first { !$0.isDone } }

    /// The single "Next:" line used on Home and on audition cards.
    var nextAction: String {
        if status == .sent { return shareLinkTimeLeft.map { "Sent · link active \($0)" } ?? "Sent" }
        guard let next = nextPiece else { return "Watch it once, then send" }
        switch next.kind {
        case .headshot:   return "Take your headshot"
        case .slate:      return "Record the slate"
        case .fullLength: return "Record the full-length shot"
        case .scene:      return "Record \(next.title)"
        }
    }

    var hoursLeft: Int { max(0, Int(due.timeIntervalSinceNow / 3600)) }

    /// The filename casting sites expect: LASTNAME_FIRSTNAME_ROLE_PROJECT.mp4, computed from the
    /// real slate and role instead of a hardcoded example.
    func deliverableFileName(slate: SlateInfo) -> String {
        func token(_ s: String) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }
        let parts = slate.name.split(separator: " ")
        let last = parts.last.map(String.init) ?? "ACTOR"
        let first = parts.count > 1 ? String(parts.first!) : ""
        let pieces = [token(last), token(first), token(role), token(project)].filter { !$0.isEmpty }
        return pieces.joined(separator: "_") + ".mp4"
    }
}

// MARK: - Takes

struct Take: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: Int
    var duration: TimeInterval
    var recordedAt: Date
    var isCircled: Bool
    var notes: [String]
    var fileURL: URL?
    /// Which audition/scene this take belongs to. Real takes created by `ShootFlow` always set
    /// both; optional only so `Take` can still be constructed in previews/tests without one.
    var auditionID: Audition.ID?
    var sceneIndex: Int?
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
}

// MARK: - Practice

struct PracticePiece: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var detail: String
    var linesLearned: Int
    var linesTotal: Int
    /// Who this piece is played against, when it's tied to a real scene (lets a Quick Drill operate on it).
    var character: String = ""
    var scene: ScriptScene? = nil
    /// Real count of practice takes recorded for this piece — never sent, but genuinely saved to disk.
    var takesRecorded: Int = 0
    /// Which audition this piece's scene came from, so Quick Drills can find real scene content.
    var auditionID: Audition.ID? = nil
    var sceneIndex: Int? = nil
}

// MARK: - Line learning drills (Practice tab's "Quick Drills")

/// The four rehearsal techniques on Practice's Quick Drills grid. `firstLetter` and `maskAndReveal`
/// reuse Prepare's own line-display transform; `audioGap` reuses Run Lines as-is; `handsFreeWalk` is
/// the only one with its own screen (continuous looped audio, no screen interaction at all).
enum LineLearningMode: String, CaseIterable, Identifiable, Hashable {
    case firstLetter, maskAndReveal, audioGap, handsFreeWalk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLetter:   "First-Letter Prompts"
        case .maskAndReveal: "Mask & Reveal Lines"
        case .audioGap:      "Audio Gap Rehearsal"
        case .handsFreeWalk: "Hands-Free Audio Walk"
        }
    }
    var subtitle: String {
        switch self {
        case .firstLetter:   "Replaces lines with initial letters to trigger recall"
        case .maskAndReveal: "Hides words progressively · tap to peek on hesitation"
        case .audioGap:      "Partner delivers cues, then leaves silence for your line"
        case .handsFreeWalk: "Listen to the whole scene on repeat, hands-free"
        }
    }
    var symbol: String {
        switch self {
        case .firstLetter:   "textformat"
        case .maskAndReveal: "eye.slash"
        case .audioGap:      "waveform"
        case .handsFreeWalk: "headphones"
        }
    }
}

/// Shared by Prepare's own toggle (`PrepareView.Mode`) and Practice's First-Letter / Mask & Reveal drills,
/// so the memorization mechanic is implemented exactly once.
enum LineDisplayMode { case full, firstLetters, hide }

func otLineDisplay(_ line: ScriptLine, mode: LineDisplayMode, peeked: Bool) -> String {
    guard line.isMine, !peeked else { return line.text }
    switch mode {
    case .full: return line.text
    case .hide: return "Tap to peek"
    case .firstLetters:
        return line.text.split(separator: " ").map { w in
            guard let f = w.first else { return "" }
            return String(f) + (w.count > 1 ? "—" : "")
        }.joined(separator: " ")
    }
}

// MARK: - Profile

struct SlateInfo: Hashable, Codable {
    var name: String = "Kabir Sharma"
    var height: String = "5′ 11″"
    var basedIn: String = "Mumbai"
    var representation: String = ""

    var spoken: String { "\(name). \(height). \(basedIn)." }
}
