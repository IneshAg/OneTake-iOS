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

    /// Selects meaning-bearing words for a stable practice gap. The model only chooses indices;
    /// the caller caches them so the same line never reshuffles between practice attempts.
    static func recallGapWordIndices(in line: String, level: Int) async -> Set<Int>? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 3 else { return [] }
            let count = min(max(1, level), max(1, words.count / 2))
            let indexedWords = words.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
            let prompt = """
            Choose exactly \(count) words that best carry the meaning, image, or emotional turn of this spoken line.
            Prefer concrete nouns, vivid verbs, and emotionally important adjectives. Avoid articles,
            conjunctions, and pronouns unless a pronoun is essential to the meaning. Do not rewrite the line.
            Return only a JSON array of zero-based integer word indices. Word positions:
            \(indexedWords)
            """
            do {
                let session = LanguageModelSession(instructions: "Select useful, memorable script words for a line-recall exercise. Follow the requested output format exactly.")
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0, maximumResponseTokens: 80))
                let data = Data(response.content.utf8)
                if let indices = try? JSONDecoder().decode([Int].self, from: data) {
                    let valid = Set(indices.filter {
                        words.indices.contains($0) && words[$0].contains(where: \.isLetter)
                    })
                    if valid.count == count { return valid }
                }
            } catch {
                // Use the stable local ranking below when Apple Intelligence is unavailable at runtime.
            }
        }
        #endif
        return nil
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

    /// Assembles a bounded context from the notice header, detected roles, and production /
    /// submission detail sections. This keeps later pages available without sending the whole packet.
    static func focusedContextSnippet(sourceText: String, targetRole: String?, candidateRoles: [String]) -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 3000 {
            return trimmed
        }

        let frontMatter = String(trimmed.prefix(1050))
        var sections = [frontMatter]
        var includedRanges: [Range<String.Index>] = []

        let roleToFind = targetRole?.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if let roleToFind, !roleToFind.isEmpty {
            candidates.append(roleToFind)
        }
        for r in candidateRoles where !candidates.contains(where: { $0.caseInsensitiveCompare(r) == .orderedSame }) {
            candidates.append(r)
        }

        for role in candidates.prefix(5) {
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
                   let match = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
                    .compactMap({ Range($0.range, in: trimmed) })
                    .first(where: { trimmed.distance(from: trimmed.startIndex, to: $0.lowerBound) > 900 }) {
                    matchedRange = match
                    break
                }
            }
            if matchedRange == nil {
                if let regex = try? NSRegularExpression(pattern: #"(?i)\b"# + NSRegularExpression.escapedPattern(for: role) + #"\b"#),
                   let match = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
                    .compactMap({ Range($0.range, in: trimmed) })
                    .first(where: { trimmed.distance(from: trimmed.startIndex, to: $0.lowerBound) > 900 }) {
                    matchedRange = match
                }
            }

            guard let match = matchedRange else { continue }
            let start = trimmed.index(match.lowerBound, offsetBy: -min(100, trimmed.distance(from: trimmed.startIndex, to: match.lowerBound)))
            let end = trimmed.index(match.lowerBound, offsetBy: min(500, trimmed.distance(from: match.lowerBound, to: trimmed.endIndex)))
            let range = start..<end
            guard !includedRanges.contains(where: { $0.overlaps(range) }) else { continue }
            let addition = "\n\n--- ROLE \(role.uppercased()) ---\n\(trimmed[range])"
            guard sections.joined().count + addition.count <= 2600 else { continue }
            sections.append(addition)
            includedRanges.append(range)
        }

        let detailPatterns = [
            #"(?i)callback(?:s)?\s*(?:date|window|schedule)?"#,
            #"(?i)(?:production|filming|shoot)\s+dates?"#,
            #"(?i)(?:pay|rate|compensation|stipend|union|SAG[- ]?AFTRA)"#,
            #"(?i)(?:orientation|landscape|portrait|file\s*name|filename|submission\s+instructions?)"#
        ]
        for pattern in detailPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let matchRange = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
                    .compactMap({ Range($0.range, in: trimmed) })
                    .first(where: { trimmed.distance(from: trimmed.startIndex, to: $0.lowerBound) > 900 }) else { continue }
            let start = trimmed.index(matchRange.lowerBound, offsetBy: -min(90, trimmed.distance(from: trimmed.startIndex, to: matchRange.lowerBound)))
            let end = trimmed.index(matchRange.upperBound, offsetBy: min(160, trimmed.distance(from: matchRange.upperBound, to: trimmed.endIndex)))
            let range = start..<end
            guard !includedRanges.contains(where: { $0.overlaps(range) }) else { continue }
            let addition = "\n\n--- NOTICE DETAIL ---\n\(trimmed[range])"
            guard sections.joined().count + addition.count <= 2950 else { continue }
            sections.append(addition)
            includedRanges.append(range)
        }

        return String(sections.joined().prefix(3000))
    }

    /// Secondary enrichment only: OCR and the deterministic parser own field extraction. The
    /// language model may fill a missing value when it can be tied back to the source, but it may
    /// not replace structured values or invent requirements/dates from unrelated notice sections.
    static func refineDraftWithFoundationModel(_ draft: NoticeParser.Draft, sourceText: String) async -> NoticeParser.Draft {
        let snippet = focusedContextSnippet(sourceText: sourceText, targetRole: draft.role, candidateRoles: draft.candidateRoles)
        guard !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return draft }

        let prompt = """
        You are an expert casting director assistant. Extract only values explicitly supported by this notice.
        Do not treat a synopsis, production description, rehearsal date, callback date, or script dialogue as a project title, deadline, casting office, or audition requirement.
        Do not choose a role when the notice says the actor may choose a character.
        Return each field on its own line using EXACTLY these keys (or 'None' if not mentioned):
        PROJECT: [Name of film, show, commercial, or play]
        ROLE: [Main character name being cast]
        CASTING_OFFICE: [Name of casting director or casting agency]
        SIDES_LINK: [Cloud link for script sides if mentioned]
        SUBMISSION_LINK: [Tape upload link, form, or submission email]
        GUIDANCE: [Brief director's note, tone, or character background]
        SYNOPSIS: [1-2 sentence storyline or logline of the project]
        UNION_STATUS: [Union status, e.g. SAG-AFTRA, Non-Union, Equity, ACTRA]
        PAY_TERMS: [Compensation, day rate, buyout, or unpaid/copy/credit]
        LOCATION: [Filming or production location/city]
        CALLBACK_DATES: [Callback date, range, or window]
        SHOOT_DATES: [Shoot dates, principal photography date range]
        ORIENTATION: [Horizontal / Landscape or Vertical / Portrait]
        FILE_NAMING: [Exact video filename convention or instructions]

        Casting Notice:
        \(snippet)

        Current known details (do not contradict if accurate):
        Project: \(draft.project.isEmpty ? "Unknown" : draft.project)
        Role: \(draft.role.isEmpty ? "Unknown" : draft.role)
        Candidate roles: \(draft.candidateRoles.isEmpty ? "Unknown" : draft.candidateRoles.joined(separator: ", "))
        """

        guard let answer = await respond(to: prompt) else { return draft }
        return applyGroundedFieldOutput(answer, to: draft, sourceText: sourceText)
    }

    /// Applies a model response without invoking a model, so source grounding can be audited and
    /// exercised independently on a deterministic test corpus.
    static func applyGroundedFieldOutput(_ answer: String, to draft: NoticeParser.Draft, sourceText: String) -> NoticeParser.Draft {
        var refined = draft

        let lines = answer.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("PROJECT:") {
                let val = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if refined.project.isEmpty && !NoticeParser.isNoticeOnly(sourceText) && isGroundedProjectTitle(val, in: sourceText) {
                    refined.project = val
                }
            } else if trimmed.uppercased().hasPrefix("ROLE:") {
                let val = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let normalizedRole = val.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " \t.,:;!?()[]{}\"'"))
                let supportedRole = refined.candidateRoles.first { $0.caseInsensitiveCompare(val) == .orderedSame }
                let explicitlyNamedRole = sourceText.range(of: #"(?i)\b(?:role|character|part)\s*[:\-]\s*"# + NSRegularExpression.escapedPattern(for: val), options: .regularExpression) != nil
                let roleIsSupported = supportedRole != nil || (refined.candidateRoles.isEmpty && explicitlyNamedRole)
                if refined.role.isEmpty && !NoticeParser.containsOpenRoleChoice(in: sourceText) && normalizedRole != "none" &&
                    !val.isEmpty && val.count <= 35 && roleIsSupported && refined.candidateRoles.count <= 1 {
                    refined.role = supportedRole ?? val
                    if !refined.candidateRoles.contains(where: { $0.caseInsensitiveCompare(refined.role) == .orderedSame }) {
                        refined.candidateRoles.append(refined.role)
                    }
                }
            } else if trimmed.uppercased().hasPrefix("CASTING_OFFICE:") {
                let val = String(trimmed.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                if refined.castingOffice.isEmpty && isGroundedCastingOffice(val, in: sourceText) {
                    refined.castingOffice = val
                }
            } else if trimmed.uppercased().hasPrefix("SIDES_LINK:") {
                let val = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if refined.sidesLink == nil && !val.isEmpty && val.lowercased() != "none" && sourceText.contains(val) {
                    refined.sidesLink = val
                }
            } else if trimmed.uppercased().hasPrefix("SUBMISSION_LINK:") {
                let val = String(trimmed.dropFirst(16)).trimmingCharacters(in: .whitespaces)
                let isLinkOrEmail = val.contains("@") || val.contains("http://") || val.contains("https://") ||
                    val.contains(".com") || val.contains(".org") || val.contains(".net") || val.contains(".in") || val.contains(".io")
                if refined.destinationDetail == nil && !val.isEmpty && val.lowercased() != "none" && isLinkOrEmail && sourceText.contains(val) {
                    refined.destinationDetail = val
                    refined.destination = val.contains("@") ? .email : .emailOrLink
                    refined.destinationWasDetected = true
                }
            } else if trimmed.uppercased().hasPrefix("GUIDANCE:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if refined.aiGuidance.isEmpty && !val.isEmpty && val.lowercased() != "none" && hasExplicitGuidanceSection(in: sourceText) {
                    refined.aiGuidance = val
                }
            } else if trimmed.uppercased().hasPrefix("SYNOPSIS:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !NoticeParser.isNoticeOnly(sourceText) && isGroundedSynopsis(val, in: sourceText) {
                    if refined.projectDetails == nil { refined.projectDetails = AuditionProjectDetails() }
                    if refined.projectDetails?.synopsis == nil || refined.projectDetails?.synopsis?.isEmpty == true {
                        refined.projectDetails?.synopsis = val
                    }
                }
            } else if trimmed.uppercased().hasPrefix("UNION_STATUS:") {
                let val = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                if isGroundedInSection(val, anchors: #"(?i)\b(?:union|SAG[- ]?AFTRA|AEA|Equity|ACTRA|non[- ]?union)\b"#, source: sourceText) {
                    if refined.projectDetails == nil { refined.projectDetails = AuditionProjectDetails() }
                    if refined.projectDetails?.unionStatus == nil || refined.projectDetails?.unionStatus?.isEmpty == true {
                        refined.projectDetails?.unionStatus = val
                    }
                }
            } else if trimmed.uppercased().hasPrefix("PAY_TERMS:") {
                let val = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                if isGroundedInSection(val, anchors: #"(?i)\b(?:pay|paid|stipend|salary|rate|compensation|honorarium|buyout|per\s+diem)\b"#, source: sourceText) {
                    if refined.projectDetails == nil { refined.projectDetails = AuditionProjectDetails() }
                    if refined.projectDetails?.payTerms == nil || refined.projectDetails?.payTerms?.isEmpty == true {
                        refined.projectDetails?.payTerms = val
                    }
                }
            } else if trimmed.uppercased().hasPrefix("LOCATION:") {
                let val = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if isGroundedInSection(val, anchors: #"(?i)\b(?:production\s+location|filming\s+location|location|filming\s+in|shooting\s+in|based\s+in|located\s+in)\b"#, source: sourceText) {
                    if refined.projectDetails == nil { refined.projectDetails = AuditionProjectDetails() }
                    if refined.projectDetails?.productionLocation == nil || refined.projectDetails?.productionLocation?.isEmpty == true {
                        refined.projectDetails?.productionLocation = val
                    }
                }
            } else if trimmed.uppercased().hasPrefix("CALLBACK_DATES:") {
                let val = String(trimmed.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                if let date = groundedMilestoneDate(val, kind: .callback, sourceText: sourceText) {
                    if !refined.importantDates.contains(where: { $0.kind == .callback }) {
                        refined.importantDates.append(date)
                    }
                }
            } else if trimmed.uppercased().hasPrefix("SHOOT_DATES:") {
                let val = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                if let date = groundedMilestoneDate(val, kind: .productionStart, sourceText: sourceText) {
                    if !refined.importantDates.contains(where: { $0.kind == .productionStart }) {
                        refined.importantDates.append(date)
                    }
                }
            } else if trimmed.uppercased().hasPrefix("ORIENTATION:") {
                let val = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                if isGroundedOrientation(val, in: sourceText) {
                    if refined.submissionInstructions == nil { refined.submissionInstructions = AuditionSubmissionInstructions() }
                    let isLandscape = val.lowercased().contains("horizontal") || val.lowercased().contains("landscape")
                    let isPortrait = val.lowercased().contains("vertical") || val.lowercased().contains("portrait")
                    if isLandscape {
                        refined.submissionInstructions?.videoOrientation = "Landscape"
                        if !refined.asks.contains("Horizontal framing") && !refined.asks.contains("Landscape") {
                            refined.asks.append("Horizontal framing")
                        }
                    } else if isPortrait {
                        refined.submissionInstructions?.videoOrientation = "Portrait"
                        if !refined.asks.contains("Vertical framing") && !refined.asks.contains("Portrait") {
                            refined.asks.append("Vertical framing")
                        }
                    }
                }
            } else if trimmed.uppercased().hasPrefix("FILE_NAMING:") {
                let val = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                if isGroundedInSection(val, anchors: #"(?i)\b(?:file\s*name|filename|naming\s+convention|name\s+(?:each|all)\s+files?)\b"#, source: sourceText) {
                    if refined.submissionInstructions == nil { refined.submissionInstructions = AuditionSubmissionInstructions() }
                    if refined.submissionInstructions?.fileNamingRule == nil {
                        refined.submissionInstructions?.fileNamingRule = val
                    }
                    if refined.submissionInstructions?.fileNameTemplate == nil {
                        let detected = NoticeParser.detectFileNamingInstruction(in: val)
                        refined.submissionInstructions?.fileNameTemplate = detected.template
                    }
                }
            }
        }

        return refined
    }

    private static func isGroundedProjectTitle(_ value: String, in source: String) -> Bool {
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'.,;:-"))
        guard !candidate.isEmpty, candidate.count <= 50, candidate.lowercased() != "none" else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: candidate)
        let anchoredPatterns = [
            #"(?i)\b(?:project(?:\s+(?:name|title|folder))?|film title|series title|show title|title|titled|called)\s*[:\-]?\s*[\"“']?"# + escaped,
            #"(?i)\b(?:world premiere(?: production)?|premiere production|production|staging|revival|adaptation)\s+of\s+[\"“']?"# + escaped
        ]
        return anchoredPatterns.contains { source.range(of: $0, options: .regularExpression) != nil }
    }

    /// Rejects model values that cannot be traced to wording in the imported document.
    /// Exact normalized matches are preferred; a high content-word overlap allows harmless
    /// punctuation and formatting differences while rejecting unsupported additions.
    private static func isGroundedNoticeValue(_ value: String, in source: String) -> Bool {
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’.,;:-"))
        guard !candidate.isEmpty, candidate.count <= 260,
              !["none", "unknown", "not specified", "n/a"].contains(candidate.lowercased()) else { return false }

        let candidateTokens = candidate.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let sourceTokenList = source.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if !candidateTokens.isEmpty, candidateTokens.count <= sourceTokenList.count {
            for start in 0...(sourceTokenList.count - candidateTokens.count) {
                if Array(sourceTokenList[start..<(start + candidateTokens.count)]) == candidateTokens { return true }
            }
        }

        let stopWords: Set<String> = ["the", "and", "for", "with", "from", "that", "this", "will", "are", "was", "has", "have", "per"]
        let evidenceTokens = candidateTokens.filter { $0.count > 2 || $0.allSatisfy(\.isNumber) }.filter { !stopWords.contains($0) }
        let sourceTokens = Set(sourceTokenList)
        guard !evidenceTokens.isEmpty else { return false }
        // Numeric details (rates, dates, age ranges) must match the source exactly.
        let numbers = evidenceTokens.filter { $0.allSatisfy(\.isNumber) }
        guard numbers.allSatisfy(sourceTokens.contains) else { return false }
        let matched = evidenceTokens.filter(sourceTokens.contains).count
        return Double(matched) / Double(evidenceTokens.count) >= 0.78
    }

    private static func hasExplicitSynopsisSection(in source: String) -> Bool {
        source.range(of: #"(?i)\b(?:about\s+the\s+project|project\s+synopsis|synopsis|logline)\s*[:\-]"#, options: .regularExpression) != nil
    }

    private static func isGroundedSynopsis(_ value: String, in source: String) -> Bool {
        hasExplicitSynopsisSection(in: source) && isGroundedInSection(
            value,
            anchors: #"(?i)\b(?:about\s+the\s+project|project\s+synopsis|synopsis|logline)\b"#,
            source: source
        )
    }

    private static func isGroundedInSection(_ value: String, anchors: String, source: String) -> Bool {
        guard isFoundNearAnchor(anchors, in: source),
              let anchorRegex = try? NSRegularExpression(pattern: anchors) else { return false }
        let lines = source.components(separatedBy: .newlines)
        for index in lines.indices where anchorRegex.firstMatch(in: lines[index], range: NSRange(lines[index].startIndex..., in: lines[index])) != nil {
            let lower = max(lines.startIndex, index - 2)
            let upper = min(lines.index(before: lines.endIndex), index + 2)
            let context = lines[lower...upper].joined(separator: "\n")
            if isGroundedNoticeValue(value, in: context) { return true }
        }
        return false
    }

    private static func isFoundNearAnchor(_ pattern: String, in source: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let lines = source.components(separatedBy: .newlines)
        for index in lines.indices {
            let lower = max(lines.startIndex, index - 2)
            let upper = min(lines.index(before: lines.endIndex), index + 2)
            let context = lines[lower...upper].joined(separator: "\n")
            if regex.firstMatch(in: context, range: NSRange(context.startIndex..., in: context)) != nil { return true }
        }
        return false
    }

    private static func hasPairedSectionAnchors(_ first: String, _ second: String, in source: String) -> Bool {
        guard let firstRegex = try? NSRegularExpression(pattern: first),
              let secondRegex = try? NSRegularExpression(pattern: second) else { return false }
        let lines = source.components(separatedBy: .newlines)
        for index in lines.indices {
            let lower = max(lines.startIndex, index - 2)
            let upper = min(lines.index(before: lines.endIndex), index + 2)
            let context = lines[lower...upper].joined(separator: "\n")
            let range = NSRange(context.startIndex..., in: context)
            if firstRegex.firstMatch(in: context, range: range) != nil,
               secondRegex.firstMatch(in: context, range: range) != nil { return true }
        }
        return false
    }

    private static func isGroundedOrientation(_ value: String, in source: String) -> Bool {
        let requested = value.lowercased()
        if requested.contains("landscape") || requested.contains("horizontal") {
            return hasPairedSectionAnchors(
                #"(?i)\b(?:landscape|horizontal)\b"#,
                #"(?i)\b(?:orientation|framing|format|record|shoot|film|video)\b"#,
                in: source
            )
        }
        if requested.contains("portrait") || requested.contains("vertical") {
            return hasPairedSectionAnchors(
                #"(?i)\b(?:portrait|vertical)\b"#,
                #"(?i)\b(?:orientation|framing|format|record|shoot|film|video)\b"#,
                in: source
            )
        }
        return false
    }

    /// Model milestone text is only useful if the source contains a dated, year-specific value.
    /// AuditionDate requires a Date, so never substitute `.now` for an imprecise phrase such as
    /// “mid-January”; the deterministic parser can still retain it if it resolves a real date.
    private static func groundedMilestoneDate(_ value: String, kind: AuditionDateKind, sourceText: String) -> AuditionDate? {
        let anchors = kind == .callback
            ? #"(?i)\b(?:callback|recall)\w*\b"#
            : #"(?i)\b(?:production|filming|shoot|principal\s+photography)\w*\b"#
        guard isGroundedNoticeValue(value, in: sourceText),
              isGroundedInSection(value, anchors: anchors, source: sourceText),
              value.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) != nil,
              let date = detectedDate(in: value) else { return nil }
        return AuditionDate(kind: kind, date: date, label: value, sourceText: value)
    }

    private static func detectedDate(in value: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return detector.matches(in: value, range: NSRange(value.startIndex..., in: value)).first?.date
    }

    private static func isGroundedCastingOffice(_ value: String, in source: String) -> Bool {
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'.,;:-"))
        guard !candidate.isEmpty, candidate.count <= 60, candidate.lowercased() != "none" else { return false }
        let lines = source.components(separatedBy: .newlines)
        for line in lines where line.range(of: candidate, options: .caseInsensitive) != nil {
            let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.hasPrefix("note on casting"), !lower.hasPrefix("a note on casting"),
                  !lower.hasPrefix("casting notes"), !lower.hasPrefix("notes from casting") else { continue }
            if lower.range(of: #"\bcasting\s+(?:director|office|company|agency)\b|\bcast by\b|\bcasting by\b"#, options: .regularExpression) != nil ||
                candidate.lowercased().contains("casting") {
                return true
            }
        }
        return false
    }

    private static func hasExplicitGuidanceSection(in source: String) -> Bool {
        source.range(of: #"(?i)\b(?:director(?:['’]s)?\s+notes?|acting notes?|tone notes?|what (?:we|i)'?re? looking for|character (?:note|brief|description|background)|role description)\s*[:\-]"#, options: .regularExpression) != nil
    }

    /// Formats and segments sides using Apple Intelligence FoundationModels when available on device (iOS 26+).
    /// If unavailable or offline, gracefully falls back to the high-precision algorithmic beat divider
    /// in ScriptParser to seamlessly guarantee natural segmentation on all iPhones.
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
        if let answer = await respond(to: prompt) {
            let lines = answer.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*•0123456789. ").union(.whitespaces)) }
                .filter { !$0.isEmpty }
            if lines.count > 1 {
                return lines
            }
        }
        // Algorithmic thought-unit fallback: 100% offline, guaranteed on all iOS versions
        let algorithmic = ScriptParser.divideIntoThoughtUnits(text)
        return algorithmic.count > 1 ? algorithmic : [text]
    }

    /// Runs 100% offline Core ML Apple Neural Engine parsing on a casting notice snippet.
    static func parseNoticeWithCoreML(text: String) async -> NoticeParser.Draft? {
        guard await CoreMLParserRunner.shared.isAvailable else { return nil }
        defer { Task { await CoreMLParserRunner.shared.unloadModel() } }
        let system = """
        You are OneTake's audition notice parser.
        Extract the casting details from the provided text into JSON:
        {"project": "Title", "project_type": "Feature film", "role": "Target Character", "candidate_roles": ["Role 1"], "role_size": "Lead", "casting_office": "Agency", "due_date": null, "specs": ["Landscape", "Slate first"], "sides_link": null, "submission_email": null, "director_guidance": null, "synopsis": null, "union_status": null, "pay_terms": null, "location": null, "callback_dates": null, "shoot_dates": null, "orientation": null, "file_naming": null}
        Output valid JSON only.
        """
        guard let jsonString = await CoreMLParserRunner.shared.generate(systemPrompt: system, userPrompt: text) else { return nil }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var draft = NoticeParser.Draft()
        let project = json["project"] as? String ?? ""
        draft.project = !NoticeParser.isNoticeOnly(text) && isGroundedProjectTitle(project, in: text) ? project : ""
        draft.candidateRoles = (json["candidate_roles"] as? [String] ?? [])
            .filter { isGroundedNoticeValue($0, in: text) }
        let role = json["role"] as? String ?? ""
        let explicitRole = !role.isEmpty && text.range(
            of: #"(?i)\b(?:role|character|part)\s*[:\-]\s*"# + NSRegularExpression.escapedPattern(for: role) + #"\b"#,
            options: .regularExpression
        ) != nil
        if !NoticeParser.containsOpenRoleChoice(in: text),
           draft.candidateRoles.count <= 1,
           (draft.candidateRoles.contains(where: { $0.caseInsensitiveCompare(role) == .orderedSame }) ||
            (draft.candidateRoles.isEmpty && explicitRole)) {
            draft.role = role
            if draft.candidateRoles.isEmpty { draft.candidateRoles = [role] }
        }
        let projectType = json["project_type"] as? String ?? ""
        if isGroundedNoticeValue(projectType, in: text) { draft.projectType = projectType }
        let roleSize = json["role_size"] as? String ?? ""
        if isGroundedNoticeValue(roleSize, in: text) { draft.roleSize = roleSize }
        let castingOffice = json["casting_office"] as? String ?? ""
        if isGroundedCastingOffice(castingOffice, in: text) { draft.castingOffice = castingOffice }
        draft.sourceText = text
        if let specs = json["specs"] as? [String] { draft.asks = specs.filter { isGroundedNoticeValue($0, in: text) } }
        if let due = json["due_date"] as? String,
           isGroundedNoticeValue(due, in: text), let date = detectedDate(in: due) { draft.due = date }
        if let email = json["submission_email"] as? String, isGroundedNoticeValue(email, in: text) {
            draft.destinationDetail = email
            draft.destination = .email
            draft.destinationWasDetected = true
        }
        if let sides = json["sides_link"] as? String, isGroundedNoticeValue(sides, in: text) { draft.sidesLink = sides }
        if let notes = json["director_guidance"] as? String,
           hasExplicitGuidanceSection(in: text), isGroundedNoticeValue(notes, in: text) { draft.castingNotes = notes }

        var details = AuditionProjectDetails()
        if let syn = json["synopsis"] as? String, isGroundedSynopsis(syn, in: text) { details.synopsis = syn }
        if let union = json["union_status"] as? String,
           isGroundedInSection(union, anchors: #"(?i)\b(?:union|SAG[- ]?AFTRA|AEA|Equity|ACTRA|non[- ]?union)\b"#, source: text) { details.unionStatus = union }
        if let pay = json["pay_terms"] as? String,
           isGroundedInSection(pay, anchors: #"(?i)\b(?:pay|paid|stipend|salary|rate|compensation|honorarium|buyout|per\s+diem)\b"#, source: text) { details.payTerms = pay }
        if let loc = json["location"] as? String,
           isGroundedInSection(loc, anchors: #"(?i)\b(?:production\s+location|filming\s+location|location|filming\s+in|shooting\s+in|based\s+in|located\s+in)\b"#, source: text) { details.productionLocation = loc }
        draft.projectDetails = details

        if let cb = json["callback_dates"] as? String,
           let date = groundedMilestoneDate(cb, kind: .callback, sourceText: text) {
            draft.importantDates.append(date)
        }
        if let shoot = json["shoot_dates"] as? String,
           let date = groundedMilestoneDate(shoot, kind: .productionStart, sourceText: text) {
            draft.importantDates.append(date)
        }

        var instructions = AuditionSubmissionInstructions()
        if let orient = json["orientation"] as? String, isGroundedOrientation(orient, in: text) {
            instructions.videoOrientation = orient.lowercased().contains("landscape") || orient.lowercased().contains("horizontal") ? "Landscape" : "Portrait"
        }
        if let fn = json["file_naming"] as? String,
           isGroundedInSection(fn, anchors: #"(?i)\b(?:file\s*name|filename|naming\s+convention|name\s+(?:each|all)\s+files?)\b"#, source: text) {
            instructions.fileNamingRule = fn
            instructions.fileNameTemplate = NoticeParser.detectFileNamingInstruction(in: fn).template
        }
        draft.submissionInstructions = instructions

        return draft
    }

    private static func respond(to prompt: String) async -> String? {
        // 1. First Priority: On-Device Apple Neural Engine Core ML Runner (iPhone 13-16, 100% offline)
        if await CoreMLParserRunner.shared.isAvailable {
            defer { Task { await CoreMLParserRunner.shared.unloadModel() } }
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
