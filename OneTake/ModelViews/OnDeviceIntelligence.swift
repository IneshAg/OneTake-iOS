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

    private static func respond(to prompt: String) async -> String? {
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
