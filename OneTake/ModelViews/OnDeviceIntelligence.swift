import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceIntelligence {
    enum TalkbackIntent: String {
        case lineComplete
        case repeatLine
        case nextLine
        case pause
        case unknown
    }

    static func talkbackIntent(spoken: String, expectedLine: String) async -> TalkbackIntent {
        let prompt = """
        Classify the actor's spoken text for a rehearsal talkback.
        Return exactly one label: lineComplete, repeatLine, nextLine, pause, or unknown.
        lineComplete means the actor delivered the expected line, including a natural paraphrase.
        repeatLine means they ask to hear the reader line again. nextLine means they ask to skip.
        pause means they ask the rehearsal to pause. Use unknown if unclear.

        Expected line: \(expectedLine)
        Actor speech: \(spoken)
        """
        guard let answer = await respond(to: prompt)?.lowercased() else { return .unknown }
        if answer.contains("repeatline") { return .repeatLine }
        if answer.contains("nextline") { return .nextLine }
        if answer.contains("pause") { return .pause }
        if answer.contains("linecomplete") { return .lineComplete }
        return .unknown
    }

    static func noticeGuidance(_ notice: String, parsed: NoticeParser.Draft) async -> String? {
        let prompt = """
        Read this casting notice and explain the practical recording checklist for the actor.
        Be concise and factual. Mention the role, requested media, framing/orientation, duration,
        deadline, and anything unclear. Do not invent missing requirements.

        Notice:
        \(notice)

        Existing deterministic extraction:
        Role: \(parsed.role.isEmpty ? "not found" : parsed.role)
        Requirements: \(parsed.asks.isEmpty ? "none found" : parsed.asks.joined(separator: ", "))
        """
        return await respond(to: prompt)
    }

    static func tapeGuidance(_ audition: Audition, report: TapeAnalyzer.Report) async -> String? {
        let findings = report.findings.map {
            "\($0.isSoftPrompt ? "OPTIONAL TIMING CUE" : "MEASURED FINDING") — \($0.category): \($0.title) (\($0.where_)) — \($0.advice)"
        }
            .joined(separator: "\n")
        let prompt = """
        Give the actor a short, supportive next-step explanation for this self-tape check.
        Use only the measured findings below and the notice requirements. Prioritize what to
        fix before recording again. Treat OPTIONAL TIMING CUE findings as uncertain and possibly
        intentional; never recommend a retake for one unless the actor says a line was lost. Do not
        grade acting, imply the actor needs a perfect score, or claim to have watched anything that is not listed.

        Notice requirements: \(audition.asks.joined(separator: ", "))
        Findings:
        \(findings.isEmpty ? "None" : findings)
        """
        return await respond(to: prompt)
    }

    static func cameraGuidance(fact: String) async -> String? {
        let prompt = """
        Turn this measured camera-framing instruction into one short spoken instruction for an actor.
        Do not add a new measurement or instruction. Use plain language and no greeting.
        Measured instruction: \(fact)
        """
        return await respond(to: prompt)
    }

    struct ExtractedNoticeMetadata {
        var project: String?
        var roles: [String]
        var asks: [String]
        var deadline: String?
    }

    /// Chained Micro-Prompt 1: Fast metadata & character extraction for the notice/cover page.
    static func extractNoticeMetadata(from text: String) async -> ExtractedNoticeMetadata? {
        let snippet = String(text.prefix(2500))
        let prompt = """
        You are a casting director assistant. Analyze this casting document or audition breakdown snippet.
        Extract the following items in plain lines:
        PROJECT: [Name of project/production, or None]
        ROLES: [Comma-separated character names auditioning, e.g. Noor, Maryam, Nadia]
        DEADLINE: [Submission deadline, date or time, or None]
        REQUIREMENTS: [Any specific video rules like Slate first, Horizontal, Off-book, or None]

        Document:
        \(snippet)
        """
        guard let answer = await respond(to: prompt) else { return nil }
        var project: String?
        var roles: [String] = []
        var asks: [String] = []
        var deadline: String?

        let lines = answer.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("PROJECT:") {
                let val = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" { project = val }
            } else if trimmed.uppercased().hasPrefix("ROLES:") {
                let val = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" {
                    roles = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            } else if trimmed.uppercased().hasPrefix("DEADLINE:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" { deadline = val }
            } else if trimmed.uppercased().hasPrefix("REQUIREMENTS:") {
                let val = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" {
                    asks = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            }
        }
        return ExtractedNoticeMetadata(project: project, roles: roles, asks: asks, deadline: deadline)
    }

    /// Assembles a token-budget-aware context snippet (~2,500-3,000 chars) that includes the document
    /// header/cover (project title, deadlines, general rules) plus the target character's specific
    /// sides section (director's notes, role details), so characters on later pages of multi-role PDFs
    /// are never starved of context.
    static func focusedContextSnippet(sourceText: String, targetRole: String?, candidateRoles: [String]) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 3000 {
            return trimmed
        }

        // Project cover / front matter (first 1,200 chars typically contains title, deadlines, casting office)
        let frontMatter = String(trimmed.prefix(1200))

        let roleToFind = targetRole?.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if let roleToFind, !roleToFind.isEmpty {
            candidates.append(roleToFind)
        }
        for r in candidateRoles where !candidates.contains(where: { $0.caseInsensitiveCompare(r) == .orderedSame }) {
            candidates.append(r)
        }

        var roleSnippet = ""
        for role in candidates {
            // Find role heading in the source text (e.g. "MARYAM ·", "MARYAM -", "ROLE: MARYAM", or "\nMARYAM\n")
            let escaped = NSRegularExpression.escapedPattern(for: role)
            let patterns = [
                "\\b\(escaped)\\b\\s*[·—\\-:]",
                "\\n\\s*\(escaped)\\s*\\n",
                "\\b(ROLE|CHARACTER):?\\s*\(escaped)\\b"
            ]
            var matchedRange: Range<String.Index>?
            for pat in patterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let r = Range(match.range, in: trimmed) {
                    matchedRange = r
                    break
                }
            }
            if matchedRange == nil {
                matchedRange = trimmed.range(of: role, options: .caseInsensitive)
            }

            if let match = matchedRange {
                let matchOffset = trimmed.distance(from: trimmed.startIndex, to: match.lowerBound)
                // If the match starts well past the front matter, extract this character's block
                if matchOffset > 1000 {
                    let endIdx = trimmed.index(match.lowerBound, offsetBy: min(1600, trimmed.distance(from: match.lowerBound, to: trimmed.endIndex)))
                    let section = String(trimmed[match.lowerBound..<endIdx])
                    roleSnippet = "\n\n--- [ROLE DETAILS & SIDES FOR \(role.uppercased())] ---\n\(section)"
                    break
                }
            }
        }

        if roleSnippet.isEmpty {
            return String(trimmed.prefix(3000))
        }

        return frontMatter + roleSnippet
    }

    /// Uses the on-device Foundation Model (when supported and available) to refine and enrich a parsed draft
    /// from raw casting notice text, resolving natural-language descriptions, director's notes, and ambiguous fields
    /// without overwriting validated deterministic regex fields.
    static func refineDraftWithFoundationModel(_ draft: NoticeParser.Draft, sourceText: String) async -> NoticeParser.Draft {
        let snippet = focusedContextSnippet(sourceText: sourceText, targetRole: draft.role, candidateRoles: draft.candidateRoles)
        guard !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return draft }

        let prompt = """
        You are an expert casting director assistant. Analyze this casting call notice and extract the key audition fields.
        Return each field on its own line using EXACTLY these keys (or 'None' if not mentioned):
        PROJECT: [Name of film, show, commercial, or play]
        ROLE: [Main character name being cast]
        ROLE_SIZE: [Lead / Supporting / Co-Star / Day Player / Series Regular / None]
        CASTING_OFFICE: [Name of casting director or casting agency]
        DEADLINE: [Self-tape submission due date/time, e.g. 'November 5, 2026' or 'Friday 5pm']
        REQUIREMENTS: [Any specific video rules: Slate first, Landscape, Full length, Headshots, etc.]
        SIDES_LINK: [Cloud link for script sides if mentioned]
        SUBMISSION_LINK: [Tape upload link, form, or submission email]
        GUIDANCE: [Brief director's note, tone, or character background]

        Casting Notice:
        \(snippet)

        Current known details (do not contradict if accurate):
        Project: \(draft.project.isEmpty ? "Unknown" : draft.project)
        Role: \(draft.role.isEmpty ? "Unknown" : draft.role)
        """

        guard let answer = await respond(to: prompt) else { return draft }
        var refined = draft

        let lines = answer.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("PROJECT:") {
                let val = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if refined.project.isEmpty && !val.isEmpty && val.lowercased() != "none" && val.count <= 50 {
                    refined.project = val
                }
            } else if trimmed.uppercased().hasPrefix("ROLE:") {
                let val = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if refined.role.isEmpty && !val.isEmpty && val.lowercased() != "none" && val.count <= 35 {
                    refined.role = val
                    if !refined.candidateRoles.contains(val) { refined.candidateRoles.append(val) }
                }
            } else if trimmed.uppercased().hasPrefix("ROLE_SIZE:") {
                let val = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" {
                    refined.roleSize = val
                }
            } else if trimmed.uppercased().hasPrefix("CASTING_OFFICE:") {
                let val = String(trimmed.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                if refined.castingOffice.isEmpty && !val.isEmpty && val.lowercased() != "none" && val.count <= 50 {
                    refined.castingOffice = val
                }
            } else if trimmed.uppercased().hasPrefix("DEADLINE:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if refined.due == nil && !val.isEmpty && val.lowercased() != "none" {
                    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                       let match = detector.firstMatch(in: val, range: NSRange(val.startIndex..., in: val)),
                       let date = match.date {
                        refined.due = date
                    }
                }
            } else if trimmed.uppercased().hasPrefix("REQUIREMENTS:") {
                let val = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty && val.lowercased() != "none" {
                    let items = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    for item in items where !item.isEmpty && !refined.asks.contains(item) {
                        refined.asks.append(item)
                    }
                }
            } else if trimmed.uppercased().hasPrefix("SIDES_LINK:") {
                let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if refined.sidesLink == nil && !val.isEmpty && val.lowercased() != "none" && sourceText.contains(val) {
                    refined.sidesLink = val
                }
            } else if trimmed.uppercased().hasPrefix("SUBMISSION_LINK:") {
                let val = String(trimmed.dropFirst(16)).trimmingCharacters(in: .whitespaces)
                if refined.destinationDetail == nil && !val.isEmpty && val.lowercased() != "none" && sourceText.contains(val) {
                    refined.destinationDetail = val
                    refined.destination = .emailOrLink
                }
            } else if trimmed.uppercased().hasPrefix("GUIDANCE:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if refined.aiGuidance.isEmpty && !val.isEmpty && val.lowercased() != "none" {
                    refined.aiGuidance = val
                }
            }
        }

        return refined
    }

    /// Formats and segments sides using Apple Intelligence FoundationModels when available on device (iOS 26+).
    /// If unavailable or offline, returns nil, allowing the high-precision algorithmic beat divider
    /// in ScriptParser to seamlessly handle segmentation on all iPhones.
    static func formatAndSegmentSides(text: String, character: String) async -> [String]? {
        let prompt = """
        You are a professional acting coach and screenplay teleprompter formatter.
        Your task is to take an actor's monologue or dialogue lines and divide them into natural, deliverable "thought units" (breath beats) for an on-camera audition teleprompter.

        Rules:
        1. Length: Each beat must be 1 to 2 sentences, between 8 and 22 words long. Never output a giant paragraph.
        2. Natural Beats: Break at dramatic pauses, full stops (. ! ?), or major clause breaks (—, ;).
        3. Do not alter, add, or skip the actor's words. Preserve their exact words.
        4. Remove any stage directions in brackets or parentheses like [speaking on phone] or (beat).
        5. Output format: Return only the deliverable beats, one beat per line, with no bullet points, no numbering, and no character prefixes.

        Character: \(character)
        Text:
        \(text)
        """
        guard let answer = await respond(to: prompt) else { return nil }
        let lines = answer.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*•0123456789. ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        return lines.count > 1 ? lines : nil
    }

    /// Runs 100% offline Core ML Apple Neural Engine parsing on a casting notice snippet.
    static func parseNoticeWithCoreML(text: String) async -> NoticeParser.Draft? {
        guard await CoreMLParserRunner.shared.isAvailable else { return nil }
        let system = """
        You are OneTake's audition notice parser.
        Extract the casting details from the provided text into JSON:
        {"project": "Title", "project_type": "Feature film", "role": "Target Character", "candidate_roles": ["Role 1"], "role_size": "Lead", "casting_office": "Agency", "due_date": null, "specs": ["Landscape", "Slate first"], "sides_link": null, "submission_email": null, "director_guidance": null}
        Output valid JSON only.
        """
        guard let jsonString = await CoreMLParserRunner.shared.generate(systemPrompt: system, userPrompt: text) else { return nil }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var draft = NoticeParser.Draft()
        draft.project = json["project"] as? String ?? ""
        draft.role = json["role"] as? String ?? ""
        draft.candidateRoles = json["candidate_roles"] as? [String] ?? []
        draft.roleSize = json["role_size"] as? String ?? "Lead"
        draft.castingOffice = json["casting_office"] as? String ?? ""
        draft.sourceText = text
        if let specs = json["specs"] as? [String] { draft.asks = specs }
        if let email = json["submission_email"] as? String { draft.destinationDetail = email; draft.destination = .emailOrLink }
        if let sides = json["sides_link"] as? String { draft.sidesLink = sides }
        if let notes = json["director_guidance"] as? String { draft.castingNotes = notes }
        return draft
    }

    private static func respond(to prompt: String) async -> String? {
        // 1. First Priority: On-Device Apple Neural Engine Core ML Runner (iPhone 13-16, 100% offline)
        if await CoreMLParserRunner.shared.isAvailable {
            if let output = await CoreMLParserRunner.shared.generate(userPrompt: prompt) {
                return output
            }
        }

        // 2. Second Priority: FoundationModels on iOS 26+ (Apple Intelligence)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: "You are a precise on-device self-tape assistant.")
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
