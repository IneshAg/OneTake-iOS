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
        case .emailOrLink:     "Private link · 30 days"
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
    var destination: Destination
    var status: AuditionStatus
    var sentDate: Date?
    var headshotAsset: String = "Headshot"

    var readyCount: Int { pieces.filter(\.isDone).count }
    var totalCount: Int { pieces.count }
    var nextPiece: Piece? { pieces.first { !$0.isDone } }

    /// The single "Next:" line used on Home and on audition cards.
    var nextAction: String {
        if status == .sent { return "Sent · link active" }
        guard let next = nextPiece else { return "Watch it once, then send" }
        switch next.kind {
        case .headshot:   return "Take your headshot"
        case .slate:      return "Record the slate"
        case .fullLength: return "Record the full-length shot"
        case .scene:      return "Record \(next.title)"
        }
    }

    var hoursLeft: Int { max(0, Int(due.timeIntervalSinceNow / 3600)) }
}

// MARK: - Takes

struct Take: Identifiable, Hashable {
    var id = UUID()
    var number: Int
    var duration: TimeInterval
    var recordedAt: Date
    var isCircled: Bool
    var notes: [String]
    var fileURL: URL?
}

// MARK: - Tape check

struct TapeFinding: Identifiable, Hashable {
    var id = UUID()
    var category: String
    var title: String
    var where_: String
    var advice: String
}

// MARK: - Schedule / practice

struct ScheduleItem: Identifiable, Hashable {
    var id = UUID()
    var when: String
    var time: String
    var title: String
    var detail: String
}

struct PracticePiece: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var linesLearned: Int
    var linesTotal: Int
    /// Who this piece is played against, when it's tied to a real scene (lets a Quick Drill operate on it).
    var character: String = ""
    var scene: ScriptScene? = nil
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
