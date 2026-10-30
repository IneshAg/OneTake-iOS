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
