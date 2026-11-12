import Foundation

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
    case firstLetter, maskAndReveal, gapRecall, audioGap, handsFreeWalk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLetter:   "First-Letter Prompts"
        case .maskAndReveal: "Mask & Reveal Lines"
        case .gapRecall: "Meaningful Word Gaps"
        case .audioGap:      "Audio Gap Rehearsal"
        case .handsFreeWalk: "Hands-Free Audio Walk"
        }
    }
    var subtitle: String {
        switch self {
        case .firstLetter:   "Replaces lines with initial letters to trigger recall"
        case .maskAndReveal: "Hides words progressively · tap to peek on hesitation"
        case .gapRecall: "Hides important words · tap a gap to reveal a clue"
        case .audioGap:      "Partner delivers cues, then leaves silence for your line"
        case .handsFreeWalk: "Listen to the whole scene on repeat, hands-free"
        }
    }
    var symbol: String {
        switch self {
        case .firstLetter:   "textformat"
        case .maskAndReveal: "eye.slash"
        case .gapRecall: "text.word.spacing"
        case .audioGap:      "waveform"
        case .handsFreeWalk: "headphones"
        }
    }
}

/// Shared by Prepare's own toggle (`PrepareView.Mode`) and Practice's First-Letter / Mask & Reveal drills,
/// so the memorization mechanic is implemented exactly once. `masked(level:)` hides a growing share
/// of your words — 1 of every 4 at level 1, every word at level 4.
enum LineDisplayMode: Hashable { case full, firstLetters, hide, masked(level: Int) }

enum StandaloneDisplay: String, CaseIterable, Hashable, Identifiable {
    case full = "Full lines"
    case firstLetters = "First letters"
    case gaps = "Gaps"
    case hideMine = "Hide my lines"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full"
        case .firstLetters: return "First letters"
        case .gaps: return "Gaps"
        case .hideMine: return "Hide mine"
        }
    }

    var lineDisplayMode: LineDisplayMode {
        switch self {
        case .full: return .full
        case .firstLetters: return .firstLetters
        case .gaps: return .masked(level: 2)
        case .hideMine: return .hide
        }
    }
}

/// Persistent, on-device word selection for a line-recall gap. Keying by normalized line text makes
/// the chosen words stable even when a scene is reloaded with newly decoded line IDs.
enum RecallGapSelectionStore {
    private static let prefix = "practice.recallGap.v2."
    private static let commonWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "than", "so", "because", "as",
        "of", "at", "by", "for", "from", "in", "into", "on", "onto", "to", "with", "about",
        "i", "me", "my", "mine", "we", "us", "our", "you", "your", "yours", "he", "him", "his",
        "she", "her", "hers", "they", "them", "their", "it", "its", "this", "that", "these", "those",
        "am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has",
        "had", "can", "could", "will", "would", "shall", "should", "may", "might", "must", "not",
        "very", "just", "really", "still", "well"
    ]

    static func hiddenWordIndices(for line: String, level: Int = 2) async -> Set<Int> {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3 else { return [] }
        let targetCount = min(max(1, level), max(1, words.count / 2))
        let key = cacheKey(for: line) + ".\(targetCount)"
        if let saved = UserDefaults.standard.array(forKey: key) as? [Int] {
            return Set(saved.filter { words.indices.contains($0) })
        }
        let modelChoice = await OnDeviceIntelligence.recallGapWordIndices(in: line, level: targetCount)
        let chosen = modelChoice ?? deterministicChoice(words: words, count: targetCount)
        let valid = Set(chosen.filter { words.indices.contains($0) })
        UserDefaults.standard.set(Array(valid).sorted(), forKey: key)
        return valid
    }

    private static func deterministicChoice(words: [String], count: Int) -> Set<Int> {
        let ranked = words.indices.compactMap { index -> (Int, Int)? in
            let clean = words[index].trimmingCharacters(in: .punctuationCharacters).lowercased()
            let letters = clean.filter(\.isLetter)
            guard !letters.isEmpty else { return nil }
            let score = (commonWords.contains(clean) ? -8 : 0)
                + min(letters.count, 12)
                + (letters.contains(where: { "aeiou".contains($0) }) ? 2 : 0)
            return (index, score)
        }
        return Set(ranked.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }.prefix(count).map(\.0))
    }

    private static func cacheKey(for line: String) -> String {
        // FNV-1a keeps the UserDefaults key short without persisting the script text itself.
        var hash: UInt64 = 14695981039346656037
        for byte in line.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return prefix + String(hash, radix: 16)
    }
}

enum PracticeRecordMode: String, CaseIterable, Hashable, Identifiable {
    case camera = "Camera"
    case voiceOnly = "Voice only"

    var id: String { rawValue }
}

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
