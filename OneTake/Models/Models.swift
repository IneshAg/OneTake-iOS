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
    case backstage = "Backstage"
    case castingNetworks = "Casting Networks"
    case spotlight = "Spotlight"
    case email = "Direct Email"
    case localFiles = "Save to Files / AirDrop"
    case emailOrLink = "Email or link"

    var id: String { rawValue }
    var spec: String {
        switch self {
        case .actorsAccess:    "H.264 .mp4 · separate clips or full tape · under 500 MB"
        case .backstage:       "H.264 .mp4 · 1080p · application upload"
        case .castingNetworks: "H.264 .mp4 · 1080p · up to 300 MB"
        case .spotlight:       "H.264 .mp4 · 1080p"
        case .email:           "Email tape or link directly to casting office"
        case .localFiles:      "Export .mp4 video, separate clips .zip, or photos to iPhone Files"
        case .emailOrLink:     "Shareable link (Drive / iCloud) for external forms"
        }
    }

    var icon: String {
        switch self {
        case .actorsAccess:    return "ticket.fill"
        case .backstage:       return "theatermasks.fill"
        case .castingNetworks: return "network"
        case .spotlight:       return "sun.max.fill"
        case .email:           return "envelope.fill"
        case .localFiles:      return "folder.fill"
        case .emailOrLink:     return "link"
        }
    }
}

/// The deliverable packaging choice: single composed video, separate clips ZIP archive, headshots, or all deliverables.
enum PackageDeliverable: String, Codable, CaseIterable, Identifiable {
    case combinedVideo = "Combined Video (.mp4)"
    case separateZip = "Separate Clips (.zip)"
    case headshotsOnly = "Headshots / Photos"
    case completePackage = "Full Package (Video + ZIP + Photos)"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .combinedVideo: return "Video (.mp4)"
        case .separateZip: return "Clips (.zip)"
        case .headshotsOnly: return "Photos"
        case .completePackage: return "All Deliverables"
        }
    }

    var subtitle: String {
        switch self {
        case .combinedVideo:
            return "Slate + scenes joined in order (H.264 1080p)"
        case .separateZip:
            return "Individual scene takes, separate slate video, and photos"
        case .headshotsOnly:
            return "Captured high-res audition headshots"
        case .completePackage:
            return "Merged video deliverable, clips ZIP, and photos"
        }
    }

    var icon: String {
        switch self {
        case .combinedVideo: return "film"
        case .separateZip: return "doc.zipper"
        case .headshotsOnly: return "photo.on.rectangle"
        case .completePackage: return "shippingbox.fill"
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
    /// A cloud link (Google Drive, Dropbox, WeTransfer, iCloud) where the casting team has
    /// shared the script sides — distinct from `destinationDetail` which is the submission URL.
    var sidesLink: String? = nil
    var packageDeliverable: PackageDeliverable? = .combinedVideo
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

    /// Detected casting email address from requirements or destination detail.
    var castingEmail: String? {
        if let direct = destinationDetail, direct.contains("@") {
            return direct.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for ask in asks {
            if ask.hasPrefix("Email: ") {
                let addr = ask.replacingOccurrences(of: "Email: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if addr.contains("@") { return addr }
            }
            if ask.contains("@") {
                let parts = ask.split(whereSeparator: \.isWhitespace)
                if let found = parts.first(where: { $0.contains("@") }) {
                    return String(found).trimmingCharacters(in: CharacterSet(charactersIn: ".,;\"'()<>"))
                }
            }
        }
        return nil
    }

    /// Automatically formats subject line based on notice instructions (e.g. Mention "Escape Plan" in subject) or standard casting protocol.
    func emailSubject(slate: SlateInfo) -> String {
        let actorName = slate.isEmpty ? "Actor" : slate.name
        for ask in asks {
            let lower = ask.lowercased()
            if lower.contains("in the subject") || lower.contains("subject:") {
                let clean = ask.replacingOccurrences(of: "Mention ", with: "")
                               .replacingOccurrences(of: "mention ", with: "")
                               .replacingOccurrences(of: "in the subject", with: "")
                               .replacingOccurrences(of: "Subject:", with: "")
                               .replacingOccurrences(of: "subject:", with: "")
                               .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”"))
                if !clean.isEmpty {
                    return "\(clean) - \(role) - \(actorName)"
                }
            }
        }
        return "\(project) - \(role) - \(actorName)"
    }

    /// Professional casting submission cover email.
    func emailBody(slate: SlateInfo) -> String {
        let actorName = slate.isEmpty ? "Actor" : slate.name
        let slateDetails = slate.isEmpty ? "" : "\n• Details: \(slate.summary)"
        let agencyLine = slate.representation.isEmpty ? "" : "\n• Agency: \(slate.representation)"
        return """
        Dear Casting Team,

        Please find attached my self-tape submission for "\(project)".

        • Role: \(role)
        • Actor: \(actorName)\(slateDetails)\(agencyLine)
        • Casting Office: \(castingOffice.isEmpty ? "Casting" : castingOffice)

        Thank you for your time and consideration.

        Best regards,
        \(actorName)
        """
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
    static let contractionMap: [String: [String]] = [
        "dont": ["do", "not"],
        "cant": ["can", "not"],
        "wont": ["will", "not"],
        "im": ["i", "am"],
        "youre": ["you", "are"],
        "theyre": ["they", "are"],
        "were": ["we", "are"],
        "isnt": ["is", "not"],
        "arent": ["are", "not"],
        "wasnt": ["was", "not"],
        "werent": ["were", "not"],
        "hasnt": ["has", "not"],
        "havent": ["have", "not"],
        "hadnt": ["had", "not"],
        "wouldnt": ["would", "not"],
        "couldnt": ["could", "not"],
        "shouldnt": ["should", "not"],
        "thats": ["that", "is"],
        "whats": ["what", "is"],
        "its": ["it", "is"],
        "lets": ["let", "us"],
        "gonna": ["going", "to"],
        "wanna": ["want", "to"],
        "gotta": ["got", "to"],
        "didnt": ["did", "not"],
        "doesnt": ["does", "not"],
        "ive": ["i", "have"],
        "youve": ["you", "have"],
        "weve": ["we", "have"],
        "theyve": ["they", "have"],
        "ill": ["i", "will"],
        "youll": ["you", "will"],
        "hell": ["he", "will"],
        "shell": ["she", "will"],
        "theyll": ["they", "will"],
        "well": ["we", "will"],
        "cuz": ["because"],
        "cause": ["because"],
        "yeah": ["yes"],
        "yep": ["yes"],
        "nope": ["no"],
        "ok": ["okay"],
        "okay": ["ok"]
    ]

    static let numberWordMap: [String: String] = [
        "1": "one", "one": "1",
        "2": "two", "two": "2",
        "3": "three", "three": "3",
        "4": "four", "four": "4",
        "5": "five", "five": "5",
        "6": "six", "six": "6",
        "7": "seven", "seven": "7",
        "8": "eight", "eight": "8",
        "9": "nine", "nine": "9",
        "10": "ten", "ten": "10"
    ]

    static func cleanWord(_ raw: String) -> String {
        let punct = CharacterSet(charactersIn: ".,!?:;\"'‘’“”()[]{}—–-…")
        let trimmed = raw.trimmingCharacters(in: punct).lowercased()
        return trimmed.replacingOccurrences(of: "'", with: "")
                      .replacingOccurrences(of: "’", with: "")
    }

    static func cleanWord(_ raw: Substring) -> String {
        cleanWord(String(raw))
    }

    /// Evaluates whether two single tokens match acoustically or semantically.
    static func wordsMatch(_ w1: String, _ w2: String) -> Bool {
        if w1 == w2 { return true }
        if let num1 = numberWordMap[w1], num1 == w2 { return true }
        if let num2 = numberWordMap[w2], num2 == w1 { return true }
        // Tolerant prefix matching for trailing phonetic endings (e.g. "looking" vs "lookin")
        if w1.count >= 5 && w2.count >= 5 {
            if w1.hasPrefix(w2) || w2.hasPrefix(w1) { return true }
        }
        return false
    }

    /// Matches spoken transcript against expected text, returning exact token indices in `text.split(separator: " ")`.
    /// Uses forward-monotonic speech frontier alignment so future/repeated words (e.g. "you", "the", "I")
    /// are NEVER highlighted prematurely out of order.
    static func matchedWordIndices(in expectedText: String, transcript: String) -> Set<Int> {
        let expectedTokens = expectedText.split(separator: " ")
        guard !expectedTokens.isEmpty else { return [] }

        let spokenWords = transcript.split(separator: " ").map { cleanWord($0) }.filter { !$0.isEmpty }
        guard !spokenWords.isEmpty else { return [] }

        var matchedIndices = Set<Int>()
        var expectedPos = 0
        var spokenPos = 0

        while spokenPos < spokenWords.count && expectedPos < expectedTokens.count {
            let spoken = spokenWords[spokenPos]
            let expectedClean = cleanWord(expectedTokens[expectedPos])

            // 1. Direct match at current expected position
            if wordsMatch(expectedClean, spoken) {
                matchedIndices.insert(expectedPos)
                expectedPos += 1
                spokenPos += 1
                continue
            }

            // 2. Contraction expansion: expected is "don't", spoken is "do not"
            if let expansion = contractionMap[expectedClean],
               expansion.count == 2,
               wordsMatch(expansion[0], spoken),
               spokenPos + 1 < spokenWords.count,
               wordsMatch(expansion[1], spokenWords[spokenPos + 1]) {
                matchedIndices.insert(expectedPos)
                expectedPos += 1
                spokenPos += 2
                continue
            }

            // 3. Reverse contraction: expected is "do not", spoken is "don't"
            if expectedPos + 1 < expectedTokens.count {
                let nextExpectedClean = cleanWord(expectedTokens[expectedPos + 1])
                if let expansion = contractionMap[spoken],
                   expansion.count == 2,
                   wordsMatch(expansion[0], expectedClean),
                   wordsMatch(expansion[1], nextExpectedClean) {
                    matchedIndices.insert(expectedPos)
                    matchedIndices.insert(expectedPos + 1)
                    expectedPos += 2
                    spokenPos += 1
                    continue
                }
            }

            // 4. Lookahead in expected tokens: actor skipped 1 or 2 filler words in the script
            var matchedInLookahead = false
            for lookahead in 1...3 {
                let candidateIdx = expectedPos + lookahead
                guard candidateIdx < expectedTokens.count else { break }
                let candidateClean = cleanWord(expectedTokens[candidateIdx])
                if wordsMatch(candidateClean, spoken) {
                    matchedIndices.insert(candidateIdx)
                    expectedPos = candidateIdx + 1
                    spokenPos += 1
                    matchedInLookahead = true
                    break
                }
            }
            if matchedInLookahead { continue }

            // 5. Lookahead in spoken words: actor repeated a word, stumbled, or speech recognizer caught filler
            var matchedSpokenLookahead = false
            for lookahead in 1...2 {
                let candidateSpokenIdx = spokenPos + lookahead
                guard candidateSpokenIdx < spokenWords.count else { break }
                if wordsMatch(expectedClean, spokenWords[candidateSpokenIdx]) {
                    matchedIndices.insert(expectedPos)
                    expectedPos += 1
                    spokenPos = candidateSpokenIdx + 1
                    matchedSpokenLookahead = true
                    break
                }
            }
            if matchedSpokenLookahead { continue }

            // 6. If no match at current frontier, advance spoken position
            spokenPos += 1
        }

        return matchedIndices
    }

    static func requiredMatches(for text: String) -> Int {
        let tokens = text.split(separator: " ").map { cleanWord($0) }.filter { !$0.isEmpty }
        let count = tokens.count
        switch count {
        case 0: return 0
        case 1: return 1
        case 2: return 1
        case 3...4: return 2
        case 5...7: return max(2, Int(Double(count) * 0.50))
        default: return max(3, Int(Double(count) * 0.50))
        }
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
