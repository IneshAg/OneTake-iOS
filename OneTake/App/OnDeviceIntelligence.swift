import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceIntelligence {
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
        let findings = report.findings.map { "\($0.category): \($0.title) (\($0.where_)) — \($0.advice)" }
            .joined(separator: "\n")
        let prompt = """
        Give the actor a short, supportive next-step explanation for this self-tape check.
        Use only the measured findings below and the notice requirements. Prioritize what to
        fix before recording again. If there are no findings, say what to verify before sending.
        Do not claim to have watched anything that is not listed.

        Notice requirements: \(audition.asks.joined(separator: ", "))
        Findings:
        \(findings.isEmpty ? "None" : findings)
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
