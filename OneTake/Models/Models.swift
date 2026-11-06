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
    var isOptional: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, kind, title, detail, isDone, isOptional
    }

    init(id: UUID = UUID(), kind: PieceKind, title: String, detail: String, isDone: Bool, isOptional: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.isDone = isDone
        self.isOptional = isOptional
    }

    /// Standard capture order used when creating or migrating an audition. User reordering is
    /// persisted as the pieces array order after this initial arrangement.
    static func defaultFlowOrder(_ pieces: [Piece]) -> [Piece] {
        pieces.enumerated().sorted { lhs, rhs in
            let leftRank = flowRank(lhs.element.kind)
            let rightRank = flowRank(rhs.element.kind)
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map { $0.element }
    }

    private static func flowRank(_ kind: PieceKind) -> Int {
        switch kind {
        case .headshot: 0
        case .slate: 1
        case .fullLength: 2
        case .scene: 3
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = try container.decode(PieceKind.self, forKey: .kind)
        self.title = try container.decode(String.self, forKey: .title)
        self.detail = try container.decode(String.self, forKey: .detail)
        self.isDone = try container.decode(Bool.self, forKey: .isDone)
        self.isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
    }
}

struct ScriptLine: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var character: String
    var text: String
    var isMine: Bool

    /// A line consisting of punctuation or stage-direction reaction (e.g. "?", "...", ".", "(pause)", "(scoffs)")
    /// represents a non-verbal expression/reaction beat rather than spoken dialogue.
    var isSilentReactionCue: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" || trimmed == "..." || trimmed == "…" || trimmed == "." { return true }
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            let inner = trimmed.dropFirst().dropLast().lowercased().trimmingCharacters(in: .whitespaces)
            if ["pause", "beat", "scoffs", "shrugs", "silence", "silent", "reacts", "hesitates", "looks"].contains(inner) {
                return true
            }
        }
        return false
    }
}

struct ScriptScene: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var number: Int
    var title: String
    var heading: String
    var lines: [ScriptLine]
    var estimatedSeconds: Int = 60

    init(id: UUID = UUID(), number: Int, title: String, heading: String, lines: [ScriptLine], estimatedSeconds: Int = 60) {
        self.id = id
        self.number = number
        self.title = title
        self.heading = heading
        self.lines = lines
        self.estimatedSeconds = estimatedSeconds
    }
}

enum AuditionStatus: String, Codable, Hashable {
    case due, ready, sent
}

// MARK: - Casting notice model

enum AuditionMaterialKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case sides = "Script Sides"
    case monologue = "Solo Monologue"
    case song = "Song / Vocal"
    case movement = "Movement / Dance"
    case slateOnly = "Slate / Intro Only"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sides: return "doc.text.fill"
        case .monologue: return "person.wave.2.fill"
        case .song: return "music.note"
        case .movement: return "figure.dance"
        case .slateOnly: return "person.crop.rectangle"
        }
    }

    var shortLabel: String {
        switch self {
        case .sides: return "Sides"
        case .monologue: return "Monologue"
        case .song: return "Song"
        case .movement: return "Movement"
        case .slateOnly: return "Slate Only"
        }
    }

    var description: String {
        switch self {
        case .sides: return "Dialogue with reader lines & in-camera teleprompter"
        case .monologue: return "Continuous solo speech without reader responses"
        case .song: return "32-bar cut or full vocal performance"
        case .movement: return "Dance, combat, or physical movement reel"
        case .slateOnly: return "Direct-to-camera slate or personality chat"
        }
    }

    var requiresSides: Bool {
        self == .sides
    }
}

enum AuditionDateKind: String, Codable, CaseIterable, Hashable {
    case submissionDeadline, audition, callback, rehearsalStart, rehearsalEnd
    case productionStart, productionEnd, performanceStart, performanceEnd, other

    var title: String {
        switch self {
        case .submissionDeadline: return "Tape Deadline"
        case .audition: return "Live Audition"
        case .callback: return "Callback Window"
        case .rehearsalStart: return "Rehearsals Start"
        case .rehearsalEnd: return "Rehearsals End"
        case .productionStart: return "Filming Starts"
        case .productionEnd: return "Filming Wraps"
        case .performanceStart: return "Opening Night"
        case .performanceEnd: return "Closing Night"
        case .other: return "Milestone"
        }
    }

    var icon: String {
        switch self {
        case .submissionDeadline: return "clock.badge.exclamationmark"
        case .audition: return "person.fill.viewfinder"
        case .callback: return "arrow.triangle.2.circlepath"
        case .rehearsalStart, .rehearsalEnd: return "theatermasks.fill"
        case .productionStart, .productionEnd: return "video.fill"
        case .performanceStart, .performanceEnd: return "sparkles"
        case .other: return "calendar"
        }
    }
}

enum AuditionSourceKind: String, Codable, CaseIterable, Hashable {
    case castingNotice, roleBreakdown, scriptSides, instructions, auditionForm, socialPost, unknown
}

struct AuditionSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: AuditionSourceKind
    var url: URL? = nil
    var pageNumber: Int? = nil
    var pageCount: Int? = nil
    var parentSourceID: UUID? = nil
}

struct AuditionFieldEvidence: Identifiable, Codable, Hashable {
    var id = UUID()
    var field: String
    var sourceID: UUID
    var pageNumber: Int? = nil
    var excerpt: String
}

struct AuditionDate: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AuditionDateKind
    var date: Date
    var label: String
    var sourceID: UUID? = nil
    var pageNumber: Int? = nil
    var sourceText: String? = nil

    var formattedDate: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}

struct AuditionProjectDetails: Codable, Hashable {
    var synopsis: String? = nil
    var productionCompany: String? = nil
    var producer: String? = nil
    var director: String? = nil
    var payTerms: String? = nil
    var unionStatus: String? = nil
    var ndaNotes: String? = nil
    var castingArea: String? = nil
    var productionLocation: String? = nil
    var travelNotes: String? = nil

    var hasReviewableContent: Bool {
        [synopsis, productionCompany, producer, director, payTerms, unionStatus, ndaNotes, castingArea, productionLocation, travelNotes]
            .contains { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }
}

struct AuditionSideMaterial: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var roleName: String? = nil
    var sideNumber: String? = nil
    var pageStart: Int? = nil
    var pageEnd: Int? = nil
    var sourceID: UUID? = nil
    var sourceURL: URL? = nil
    var text: String? = nil
}

struct AuditionRoleBreakdown: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var description: String? = nil
    var ageRange: String? = nil
    var gender: String? = nil
    var ethnicity: String? = nil
    var skills: [String] = []
    var eligibilityNotes: String? = nil
    var sideMaterialIDs: [UUID] = []
}

struct AuditionSubmissionInstructions: Codable, Hashable {
    var slateRequirements: [String] = []
    var videoOrientation: String? = nil
    var requiredVideoCount: Int? = nil
    var maxTakes: Int? = nil
    var acceptedFormats: [String] = []
    var fileNamingRule: String? = nil
    /// A pattern may use {name}, {firstName}, {lastName}, {role}, {project}, {side}, {scene}, {take}, or {song}.
    var fileNameTemplate: String? = nil
    var submissionRouteNotes: String? = nil
    var otherRequirements: [String] = []
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

struct DueRemaining: Equatable, Hashable, Codable {
    var days: Int
    var hours: Int
    var minutes: Int
    var totalSeconds: TimeInterval

    var isPastDue: Bool { totalSeconds <= 0 }

    /// Short compact string for schedule rows and badges (e.g. "2d 4h", "5h", "45m")
    var compactSummary: String {
        if isPastDue { return "0m" }
        if days >= 1 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours >= 1 {
            return "\(hours)h"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    /// Full descriptive string with "left" (e.g. "2 days 4 hrs left", "5 hrs left", "45 mins left")
    var descriptiveLeft: String {
        if isPastDue { return "0 mins left" }
        if days >= 1 {
            let dayPart = "\(days) \(days == 1 ? "day" : "days")"
            if hours > 0 {
                let hrPart = "\(hours) \(hours == 1 ? "hr" : "hrs")"
                return "\(dayPart) \(hrPart) left"
            } else {
                return "\(dayPart) left"
            }
        } else if hours >= 1 {
            return "\(hours) \(hours == 1 ? "hr" : "hrs") left"
        } else {
            let m = max(1, minutes)
            return "\(m) \(m == 1 ? "min" : "mins") left"
        }
    }

    /// Relative phrase without "left" (e.g. "in 2 days 4 hrs", "in 5 hrs", "in 45 mins")
    var relativePhrase: String {
        if isPastDue { return "past due" }
        if days >= 1 {
            let dayPart = "\(days) \(days == 1 ? "day" : "days")"
            if hours > 0 {
                let hrPart = "\(hours) \(hours == 1 ? "hr" : "hrs")"
                return "in \(dayPart) \(hrPart)"
            } else {
                return "in \(dayPart)"
            }
        } else if hours >= 1 {
            return "in \(hours) \(hours == 1 ? "hr" : "hrs")"
        } else {
            let m = max(1, minutes)
            return "in \(m) \(m == 1 ? "min" : "mins")"
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
    /// Optional during migration: nil/false means the old default wasn't a user choice.
    var destinationWasChosen: Bool? = nil
    var destinationDetail: String? = nil
    /// A cloud link (Google Drive, Dropbox, WeTransfer, iCloud) where the casting team has
    /// shared the script sides — distinct from `destinationDetail` which is the submission URL.
    var sidesLink: String? = nil
    /// Reusable actor résumé selected for this audition's submission.
    var resumeURL: URL? = nil
    /// Deliberately unset until the notice specifies a format or the actor chooses one.
    var packageDeliverable: PackageDeliverable? = nil
    var status: AuditionStatus
    var sentDate: Date?

    /// Real recordings, once this audition has actually been shot — nil until then. Persisted as
    /// file URLs; the files themselves live under `MediaStore`.
    var slateVideoURL: URL?
    /// Original slate is retained when an edge-silence trim is accepted, so it can be restored.
    var slateOriginalVideoURL: URL? = nil
    var fullLengthVideoURL: URL?
    /// Original full-body shot recording retained when an edited version is chosen.
    var fullLengthOriginalVideoURL: URL? = nil
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
    /// Private rehearsal notes, subtext, objective, or character choices written by the actor.
    var actorNotes: String?
    /// Structured enrichment kept optional so auditions saved by older app versions still decode.
    var materialKind: AuditionMaterialKind? = .sides
    var projectDetails: AuditionProjectDetails? = nil
    var importantDates: [AuditionDate]? = nil
    var roleBreakdowns: [AuditionRoleBreakdown]? = nil
    var sideMaterials: [AuditionSideMaterial]? = nil
    var sourceDocuments: [AuditionSource]? = nil
    var noticeSources: [AuditionSource]? = nil
    var fieldEvidence: [AuditionFieldEvidence]? = nil
    var submissionInstructions: AuditionSubmissionInstructions? = nil

    var resolvedMaterialKind: AuditionMaterialKind { materialKind ?? .sides }

    /// "22 days" style remaining lifetime of the sent link, or nil if there's no (live) link.
    var shareLinkTimeLeft: String? {
        guard shareLink != nil, let expires = shareLinkExpires else { return nil }
        let days = Int(ceil(expires.timeIntervalSinceNow / 86400))
        return days > 0 ? "\(days) day\(days == 1 ? "" : "s")" : nil
    }

    var readyCount: Int { pieces.filter(\.isDone).count }
    var totalCount: Int { pieces.count }
    var requiredPieces: [Piece] { pieces.filter { !$0.isOptional } }
    /// True when all required pieces are completed (optional pieces do not block the package),
    /// and at least one piece is completed.
    var isPackageReady: Bool {
        guard !pieces.isEmpty, pieces.contains(where: \.isDone) else { return false }
        let req = requiredPieces
        if req.isEmpty {
            return pieces.contains { $0.isDone }
        }
        return req.allSatisfy { $0.isDone }
    }

    /// The next piece follows the actor's saved flow order. Optional pieces remain available while
    /// required work is still underway, but they do not block preview once all required pieces finish.
    var nextPiece: Piece? {
        if isPackageReady { return nil }
        return pieces.first { !$0.isDone }
    }

    /// The single "Next:" line used on Home and on audition cards.
    var nextAction: String {
        if status == .sent { return shareLinkTimeLeft.map { "Sent · link active \($0)" } ?? "Sent" }
        guard let next = nextPiece else { return "Watch it once, then send" }
        switch next.kind {
        case .headshot:   return "Take your headshot"
        case .slate:      return "Record the slate"
        case .fullLength: return "Record the full-body shot"
        case .scene:      return "Record \(next.title)"
        }
    }

    var hoursLeft: Int {
        let remaining = due.timeIntervalSinceNow
        return remaining <= 0 ? 0 : max(1, Int(remaining / 3600))
    }

    /// Remaining time until the audition deadline, broken down into days, hours, and minutes.
    var dueRemaining: DueRemaining {
        let remaining = due.timeIntervalSinceNow
        if remaining <= 0 {
            return DueRemaining(days: 0, hours: 0, minutes: 0, totalSeconds: remaining)
        }
        let totalSeconds = remaining
        let totalMinutes = Int(totalSeconds / 60)
        let totalHours = Int(totalSeconds / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        let minutes = totalMinutes % 60
        return DueRemaining(days: days, hours: hours, minutes: minutes, totalSeconds: remaining)
    }

    /// Uses a notice-provided template when one was extracted; otherwise keeps the app's stable
    /// actor/role/project filename. Supported template tokens are documented on
    /// `AuditionSubmissionInstructions.fileNameTemplate`.
    func deliverableFileName(
        slate: SlateInfo,
        side: String? = nil,
        scene: String? = nil,
        take: Int? = nil,
        song: String? = nil
    ) -> String {
        let words = slate.name.split(whereSeparator: \.isWhitespace).map(String.init)
        let first = words.first ?? "Actor"
        let last = words.count > 1 ? (words.last ?? "") : ""
        let replacements: [(String, String)] = [
            ("{firstName}", first), ("{lastName}", last), ("{name}", slate.name),
            ("{role}", role), ("{project}", project), ("{side}", side ?? ""),
            ("{scene}", scene ?? ""), ("{take}", take.map(String.init) ?? ""), ("{song}", song ?? "")
        ]

        if var template = submissionInstructions?.fileNameTemplate, !template.isEmpty {
            template = template.replacingOccurrences(of: #"(?i)\.(?:mp4|mov|m4v)$"#, with: "", options: .regularExpression)
            let available: [String: String?] = [
                "{firstname}": first.isEmpty ? nil : first,
                "{lastname}": last.isEmpty ? nil : last,
                "{name}": slate.name.isEmpty ? nil : slate.name,
                "{role}": role.isEmpty ? nil : role,
                "{project}": project.isEmpty ? nil : project,
                "{side}": side,
                "{scene}": scene,
                "{take}": take.map(String.init),
                "{song}": song
            ]
            let templateHasUnavailableToken = available.contains { token, value in
                template.localizedCaseInsensitiveContains(token) && value == nil
            }
            guard !templateHasUnavailableToken else {
                return defaultDeliverableFileName(first: first, last: last)
            }
            for (placeholder, value) in replacements {
                template = template.replacingOccurrences(of: placeholder, with: value, options: .caseInsensitive)
            }
            let safe = template
                .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
                .replacingOccurrences(of: #"[._-]{2,}"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
            if !safe.isEmpty { return (safe as NSString).appendingPathExtension("mp4") ?? "\(safe).mp4" }
        }

        return defaultDeliverableFileName(first: first, last: last)
    }

    private func defaultDeliverableFileName(first: String, last: String) -> String {
        func token(_ value: String) -> String { value.uppercased().filter { $0.isLetter || $0.isNumber } }
        let defaultParts = [last.isEmpty ? first : last, last.isEmpty ? "" : first, role, project]
            .map(token).filter { !$0.isEmpty }
        return defaultParts.joined(separator: "_") + ".mp4"
    }

    func clipFileName(slate: SlateInfo, scene: String, take: Int? = nil, side: String? = nil, extension fileExtension: String) -> String {
        let custom = deliverableFileName(slate: slate, side: side, scene: scene, take: take)
        var stem = (custom as NSString).deletingPathExtension
        let template = submissionInstructions?.fileNameTemplate?.lowercased() ?? ""
        if !template.contains("{scene}") { stem += "_\(scene)" }
        if !template.contains("{side}"), let side { stem += "_SIDE_\(side)" }
        if !template.contains("{take}"), let take { stem += "_TAKE_\(take)" }
        stem = stem.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
        return "\(stem).\(fileExtension)"
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
        let actorName = slate.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Actor" : slate.name
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
        let actorName = slate.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Actor" : slate.name
        let slateDetails = slate.summary.isEmpty ? "" : "\n• Details: \(slate.summary)"
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
    /// Kept separately after trimming so the actor can restore the recorded source clip.
    var originalFileURL: URL? = nil
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
    private static let prefix = "practice.recallGap.v1."
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
        let key = cacheKey(for: line)
        if let saved = UserDefaults.standard.array(forKey: key) as? [Int] {
            return Set(saved.filter { words.indices.contains($0) })
        }
        let targetCount = min(max(1, level), max(1, words.count / 2))
        let modelChoice = await OnDeviceIntelligence.recallGapWordIndices(in: line, level: targetCount)
        let chosen = modelChoice ?? deterministicChoice(words: words, count: targetCount)
        let valid = Set(chosen.filter { words.indices.contains($0) })
        UserDefaults.standard.set(Array(valid).sorted(), forKey: key)
        return valid
    }

    private static func deterministicChoice(words: [String], count: Int) -> Set<Int> {
        let ranked = words.indices.map { index -> (Int, Int) in
            let clean = words[index].trimmingCharacters(in: .punctuationCharacters).lowercased()
            let letters = clean.filter(\.isLetter)
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
