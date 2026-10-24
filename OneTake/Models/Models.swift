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

/// What came of a sent tape, as the actor logs it (nil = no word yet). Kept now so a stats screen
/// later has real history to count: callback and booking rates, which offices call you back.
enum AuditionOutcome: String, Codable, CaseIterable, Hashable, Identifiable {
    case callback, pinned, booked, passed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .callback: "Callback"
        case .pinned:   "Pinned"
        case .booked:   "Booked"
        case .passed:   "Not this time"
        }
    }
    var symbol: String {
        switch self {
        case .callback: "arrow.uturn.right"
        case .pinned:   "pin.fill"
        case .booked:   "star.fill"
        case .passed:   "xmark"
        }
    }
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
    /// What came of it once sent, and when that was logged. Optional so older state decodes.
    var outcome: AuditionOutcome?
    var outcomeDate: Date?

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

/// How far into one of your lines the speech recogniser has heard you. It matches the words
/// themselves rather than counting them, so a stumble, an ad-lib or the wrong line doesn't move the
/// prompter on. Shared by Run Lines and the in-camera prompter.
struct LineMatch: Equatable {
    /// Words of the line covered so far, for the highlight: up to the last one heard.
    var reached = 0
    /// Words of the line actually heard.
    var matched = 0
    var total = 0
    /// Done: the line's last word was heard, and most of the rest of it too.
    var isComplete: Bool { total > 0 && reached == total && matched * 5 >= total * 3 }
}

func otMatch(_ text: String, heard: [String]) -> LineMatch {
    let expected = otWords(text)
    var match = LineMatch(total: expected.count)
    for word in heard.flatMap(otWords) where match.reached < expected.count {
        // A few words of look-ahead, so a skipped or misheard word doesn't stall the line, but a word
        // from much later in it (or from another line) can't jump to its end.
        let window = expected[match.reached..<min(expected.count, match.reached + 3)]
        if let hit = window.firstIndex(where: { otSameWord($0, word) }) {
            match.matched += 1
            match.reached = hit + 1
        }
    }
    return match
}

/// Lowercased words, the same on both sides of a match: apostrophes dropped ("Don't" → "dont"), any
/// other punctuation splits ("you—Maya" → "you", "maya").
func otWords(_ text: String) -> [String] {
    var cleaned = String.UnicodeScalarView()
    for scalar in text.lowercased().unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) { cleaned.append(scalar) }
        else if scalar != "'" && scalar != "\u{2019}" { cleaned.append(" ") }
    }
    return String(cleaned).split(separator: " ").map(String.init)
}

private let otNumberWords: Set<String> = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
    "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
    "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "first", "second", "third"
]

/// Same word, allowing for how the recogniser writes things: digits for a spelled-out number ("20" for
/// "twenty"), and one letter off in a longer word ("color"/"colour", a misheard name).
private func otSameWord(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    let aDigits = a.allSatisfy(\.isNumber), bDigits = b.allSatisfy(\.isNumber)
    if aDigits != bDigits { return aDigits ? otNumberWords.contains(b) : otNumberWords.contains(a) }
    guard min(a.count, b.count) >= 4, abs(a.count - b.count) <= 1 else { return false }
    // Levenshtein distance ≤ 1.
    let x = Array(a), y = Array(b)
    var i = 0, j = 0, edits = 0
    while i < x.count && j < y.count {
        if x[i] == y[j] { i += 1; j += 1; continue }
        edits += 1
        if edits > 1 { return false }
        if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
    }
    return edits + (x.count - i) + (y.count - j) <= 1
}

// MARK: - Profile

struct SlateInfo: Hashable, Codable {
    var name: String = "Kabir Sharma"
    var height: String = "5′ 11″"
    var basedIn: String = "Mumbai"
    var representation: String = ""

    var spoken: String { "\(name). \(height). \(basedIn)." }
}
