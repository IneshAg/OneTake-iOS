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
    case due, ready, exported, sent
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
    var isArchived: Bool? = false
    var archived: Bool { isArchived ?? false }

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
    var sidesRevision: Int? = 0
    var currentSidesRevision: Int { sidesRevision ?? 0 }

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
    var requiredReadyCount: Int { requiredPieces.filter(\.isDone).count }
    var requiredTotalCount: Int { requiredPieces.count }
    var requiredProgressSummary: String {
        let total = requiredTotalCount > 0 ? requiredTotalCount : totalCount
        let ready = requiredTotalCount > 0 ? requiredReadyCount : readyCount
        return "\(ready) of \(total) required items ready"
    }

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

    /// The first required piece that is not yet completed, or nil when `isPackageReady` is true
    /// (all required pieces completed). If no required pieces exist, returns the first incomplete piece.
    var nextRequiredPiece: Piece? {
        if isPackageReady { return nil }
        if let nextReq = requiredPieces.first(where: { !$0.isDone }) {
            return nextReq
        }
        return pieces.first { !$0.isDone }
    }

    /// The next piece follows the actor's saved flow order. Optional pieces remain available while
    /// required work is still underway, but they do not block preview once all required pieces finish.
    var nextPiece: Piece? {
        nextRequiredPiece
    }

    /// The single "Next:" line used on Home and on audition cards.
    var nextAction: String {
        if status == .sent { return shareLinkTimeLeft.map { "Sent · link active \($0)" } ?? "Sent" }
        if status == .exported { return "Exported · Mark as Submitted" }
        guard let next = nextRequiredPiece else { return "Review & Send tape" }
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

