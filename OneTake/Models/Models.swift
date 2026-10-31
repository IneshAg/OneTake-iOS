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
    /// Original sides text lets role edits re-identify the actor's cues without losing lines that
    /// were initially treated as one-off speakers. Optional for older saved auditions.
    var scriptText: String? = nil
    var destination: Destination
    var destinationDetail: String? = nil
    var status: AuditionStatus
    var sentDate: Date?

    /// Real recordings, once this audition has actually been shot — nil until then. Persisted as
    /// file URLs; the files themselves live under `MediaStore`.
    var slateVideoURL: URL?
    /// Original slate is retained when an edge-silence trim is accepted, so it can be restored.
    var slateOriginalVideoURL: URL? = nil
    var fullLengthVideoURL: URL?
    /// The packaged deliverable, once `MediaExporter` has actually composed one.
    var exportedFileURL: URL?
    /// The separate-clip archive created alongside the merged deliverable.
    var separateArchiveURL: URL?
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

    var hoursLeft: Int {
        let remaining = due.timeIntervalSinceNow
        return remaining <= 0 ? 0 : max(1, Int(remaining / 3600))
    }

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
    /// True for heuristic timing cues that may be intentional, such as a pause or immediate start.
    var isSoftPrompt: Bool = false
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
/// so the memorization mechanic is implemented exactly once. `masked(level:)` hides a growing share
/// of your words — 1 of every 4 at level 1, every word at level 4.
enum LineDisplayMode { case full, firstLetters, hide, masked(level: Int) }

func otLineDisplay(_ line: ScriptLine, mode: LineDisplayMode, peeked: Bool) -> String {
    guard line.isMine, !peeked else { return line.text }
    switch mode {
    case .full: return line.text
    case .hide: return "Tap to peek"
    case .masked(let level):
        return line.text.split(separator: " ").enumerated().map { i, w in
            i % 4 < level ? String(repeating: "_", count: min(max(w.count, 2), 8)) : String(w)
        }.joined(separator: " ")
    case .firstLetters:
        return line.text.split(separator: " ").map { w in
            guard let f = w.first else { return "" }
            return String(f) + (w.count > 1 ? "—" : "")
        }.joined(separator: " ")
    }
}

/// Confirms that speech follows the current line before voice-controlled screens advance.
enum SpokenLineMatcher {
    static func matchedWordIndices(in expectedText: String, transcript: String) -> Set<Int> {
        let expected = words(in: expectedText)
        let spoken = words(in: transcript)
        var result = Set<Int>()
        var cursor = 0
        for (index, word) in expected.enumerated() {
            guard cursor < spoken.count else { break }
            if let match = spoken[cursor...].firstIndex(of: word) {
                result.insert(index)
                cursor = match + 1
            }
        }
        return result
    }

    static func requiredMatches(for text: String) -> Int {
        let count = words(in: text).count
        return count <= 2 ? count : Int(ceil(Double(count) * 0.8))
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

// MARK: - Profile

struct SlateInfo: Hashable, Codable {
    /// Empty until the actor fills it in: every tape opens with this and every file is named after
    /// it, so a made-up example would end up on real submissions.
    var name: String = ""
    var height: String = ""
    var basedIn: String = ""
    var representation: String = ""

    /// The design-mockup persona earlier builds pre-filled. Anyone who skipped the slate step still
    /// has it saved; it's cleared on load (see `AppStore.init`).
    static let legacyPlaceholder = SlateInfo(name: "Kabir Sharma", height: "5′ 11″", basedIn: "Mumbai", representation: "")

    var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the actor says to the lens — only the parts that are filled in.
    var spoken: String {
        guard !isEmpty else { return "Say your name, height and where you're based." }
        let punct = CharacterSet(charactersIn: " ,;.-")
        return [name, height, basedIn]
            .map { $0.trimmingCharacters(in: punct) }
            .filter { !$0.isEmpty }
            .map { $0 + "." }
            .joined(separator: " ")
    }

    /// One line for Profile: "5′ 11″ · Mumbai · Self-represented".
    var summary: String {
        let rep = representation.trimmingCharacters(in: .whitespaces)
        let parts = [height, basedIn].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (parts + [rep.isEmpty ? "Self-represented" : rep]).joined(separator: " · ")
    }
}
