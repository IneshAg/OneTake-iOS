import Foundation

// MARK: - Profile

struct SlateInfo: Hashable, Codable {
    /// Empty until the actor fills it in: every tape opens with this and every file is named after
    /// it, so a made-up example would end up on real submissions.
    var name: String = ""
    var height: String = ""
    var basedIn: String = ""
    var representation: String = ""
    /// The actor's reusable profile résumé. Each audition can choose whether to include it.
    var resumeURL: URL? = nil

    /// The design-mockup persona earlier builds pre-filled. Anyone who skipped the slate step still
    /// has it saved; it's cleared on load (see `AppStore.init`).
    static let legacyPlaceholder = SlateInfo(name: "Kabir Sharma", height: "5′ 11″", basedIn: "Mumbai", representation: "")

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
        && height.trimmingCharacters(in: .whitespaces).isEmpty
        && basedIn.trimmingCharacters(in: .whitespaces).isEmpty
        && representation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What the actor says to the lens — only the parts that are filled in.
    var spoken: String {
        let punct = CharacterSet(charactersIn: " ,;.-")
        let parts = [name, height, basedIn]
            .map { $0.trimmingCharacters(in: punct) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "Say your name, height and where you're based." }
        return parts
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
