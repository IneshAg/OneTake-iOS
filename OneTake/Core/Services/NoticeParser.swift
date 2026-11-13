import Foundation
import UIKit

enum NoticeParser {
    /// A casting notice can contain uppercase headings and bullet lists that resemble character cues.
    /// Only treat a notice-plus-sides document as script material when a scene heading is present;
    /// otherwise do not turn the notice's own headings into dialogue or a required scene.
    static func isNoticeOnly(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasNoticeMarkers = [
            "what to submit", "currently casting", "actors should email", "audition notice",
            "casting call", "we're looking for", "we are looking for", "requirement:", "requirements:",
            "kindly send in your", "send in your", "recent pictures", "upcoming project"
        ].contains(where: lower.contains)
        guard hasNoticeMarkers else { return false }
        let hasSceneMarker = text.range(of: #"(?im)^\s*(?:INT\.|EXT\.|INT/EXT\b|SCENE\s+[0-9A-Z]+\b|ACT\s+(?:ONE|TWO|THREE|[0-9IVX]+)\b|[A-Z]{2,20}\s*[·•|—-]\s*(?:He|She|They)/|[A-Z]{2,20}\s*[-—–]\s*(?:Page|Pg\.?)\s*\d+)"#, options: .regularExpression) != nil
        return !hasSceneMarker
    }

    struct Draft: Hashable, Identifiable {
        /// Stable identity so `.sheet(item:)` can distinguish different parsed drafts.
        var id: String { "\(project)|\(role)|\(castingOffice)|\(due?.timeIntervalSince1970 ?? 0)|\(sidesLink ?? "")" }
        var project = ""
        var role = ""
        var candidateRoles: [String] = []
        var castingOffice = ""
        var projectType = "Feature film"
        var due: Date?
        var scenes = 0
        var asks: [String] = []
        var aiGuidance = ""
        var roleSize = "Lead"
        /// True when the notice explicitly says sides will be provided at the audition, so
        /// `missingRequiredDetails` does not ask the actor to add them in advance.
        var sidesOnArrival = false
        /// A cloud drive link (Google Drive, Dropbox, WeTransfer, OneDrive) where script sides or materials are hosted.
        var sidesLink: String? = nil
        var destination: Destination = .actorsAccess
        var destinationDetail: String? = nil
        var destinationWasDetected = false
        /// The real recognised text this draft came from — kept so `makeAudition()` can parse real
        /// sides out of it instead of substituting a canned scene.
        var sourceText = ""
        var customScenes: [ScriptScene]? = nil
        var castingNotes: String? = nil
        var actorNotes: String? = nil
        var materialKind: AuditionMaterialKind = .sides
        var isSlateOptional: Bool = false
        var isFullBodyShotOptional: Bool = false
        var isHeadshotOptional: Bool = false
        var includeSlate: Bool = true
        var includeHeadshots: Bool = true
        var includeResume: Bool = false
        var resumeURL: URL? = nil
        var availablePortions: [ScriptParser.ScenePortion] = []
        var selectedPortionIDs: Set<String> = []
        var projectDetails: AuditionProjectDetails? = nil
        var importantDates: [AuditionDate] = []
        var roleBreakdowns: [AuditionRoleBreakdown] = []
        var sideMaterials: [AuditionSideMaterial] = []
        var noticeSources: [AuditionSource] = []
        var fieldEvidence: [AuditionFieldEvidence] = []
        var submissionInstructions: AuditionSubmissionInstructions? = nil
        var sourceDocuments: [AuditionSource] = []

        static let blank = Draft()

        var hasSides: Bool {
            if !materialKind.requiresSides { return true }
            if let customScenes, !customScenes.isEmpty { return true }
            return !NoticeParser.isNoticeOnly(sourceText) && !ScriptParser.parseScenes(from: sourceText, myRole: role).isEmpty
        }

        var missingRequiredDetails: [String] {
            var missing: [String] = []
            if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && materialKind != .slateOnly { missing.append("role") }
            if materialKind.requiresSides && !hasSides && !NoticeParser.isNoticeOnly(sourceText) && !sidesOnArrival && (sidesLink == nil || sidesLink?.isEmpty == true) { missing.append("script sides") }
            let resumeRequired = asks.contains { ask in
                let value = ask.lowercased()
                return (value == "resume" || value == "résumé") && !value.contains("optional")
            }
            if resumeRequired && (!includeResume || resumeURL == nil) { missing.append("resume") }
            return missing
        }

        func makeAudition() -> Audition {
            var parsedScenes = hasSides
                ? ((customScenes?.isEmpty == false ? customScenes : nil) ?? ScriptParser.parseScenes(from: sourceText, myRole: role))
                : []

            // Non-dialogue audition types: adapt scenes and pieces accordingly
            switch materialKind {
            case .monologue:
                if parsedScenes.isEmpty {
                    let cleaned = ScriptParser.cleanPastedText(sourceText)
                    let monologueLines = cleaned.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { ScriptLine(character: role.isEmpty ? "Actor" : role, text: $0, isMine: true) }
                    if !monologueLines.isEmpty {
                        parsedScenes = [ScriptScene(number: 1, title: "Monologue", heading: "SOLO MONOLOGUE", lines: monologueLines, estimatedSeconds: max(30, monologueLines.count * 3))]
                    }
                }
            case .song:
                if parsedScenes.isEmpty {
                    parsedScenes = [ScriptScene(number: 1, title: "Song Cut", heading: "VOCAL AUDITION", lines: [], estimatedSeconds: 90)]
                }
            case .movement:
                if parsedScenes.isEmpty {
                    parsedScenes = [ScriptScene(number: 1, title: "Movement / Dance", heading: "PHYSICAL AUDITION", lines: [], estimatedSeconds: 90)]
                }
            case .slateOnly:
                parsedScenes = []
            case .sides:
                break
            }

            var pieces: [Piece] = []
            if includeSlate || materialKind == .slateOnly {
                var slateDetail = materialKind == .slateOnly
                    ? "Direct-to-camera slate & intro"
                    : (asks.contains(where: { $0.localizedCaseInsensitiveContains("self-tape") || $0.localizedCaseInsensitiveContains("introduction video") })
                       ? "Self-tape or introduction video, as requested"
                       : "Name, height, city")
                if asks.contains("Full-body shot with slate") {
                    slateDetail += isFullBodyShotOptional ? " · optional head-to-toe view" : " · include a head-to-toe view"
                }
                pieces.append(.init(kind: .slate, title: isSlateOptional ? "Slate (Optional)" : "Slate", detail: slateDetail, isDone: false, isOptional: isSlateOptional && materialKind != .slateOnly))
            }

            if asks.contains("Full-body shot")
                || (asks.contains("Full-body shot with slate") && !includeSlate) {
                pieces.append(.init(kind: .fullLength, title: "Full-body shot",
                                    detail: "Head-to-toe video, as requested",
                                    isDone: false, isOptional: isFullBodyShotOptional))
            }

            if materialKind != .slateOnly {
                if parsedScenes.isEmpty {
                    // No sides could be read from what was captured — be honest about that rather than
                    // filling in a stand-in scene. Pieces still exist so the checklist has something to
                    // point at; "Add sides" is left for the actor to do once they have the real pages.
                    for i in 0..<max(scenes, 0) {
                        pieces.append(.init(kind: .scene, title: "Scene \(i + 1)", detail: "No sides yet — add them", isDone: false))
                    }
                } else {
                    for scene in parsedScenes {
                        let isOpt = NoticeParser.isSceneOptional(scene: scene, in: sourceText)
                        pieces.append(.init(kind: .scene, title: scene.title, detail: isOpt ? "Optional scene" : "", isDone: false, isOptional: isOpt))
                    }
                }
            }

            if includeHeadshots {
                pieces.append(.init(kind: .headshot, title: isHeadshotOptional ? "Headshot (Optional)" : "Headshot", detail: "Photos", isDone: false, isOptional: isHeadshotOptional))
            }
            pieces = Piece.defaultFlowOrder(pieces)
            let autoNotes = NoticeParser.extractCharacterDescription(for: role, in: sourceText)
            // Project-level guidance is not a character breakdown. Keep it out of the casting
            // notes column unless we have notes explicitly attached to the selected role.
            let resolvedCastingNotes = castingNotes ?? autoNotes
            let auditionName = project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled audition" : "\(role) audition")
                : project
            var audition = Audition(project: auditionName, projectType: projectType,
                            role: role.isEmpty ? (materialKind == .slateOnly ? "Self" : "Role") : role, roleSize: roleSize, castingOffice: castingOffice,
                            due: due ?? .now.addingTimeInterval(3 * 86400),
                            asks: asks, pieces: pieces, scenes: parsedScenes,
                            scriptText: sourceText.isEmpty ? nil : sourceText,
                            destination: destination, status: .due)
            audition.materialKind = materialKind
            audition.destinationWasChosen = destinationWasDetected
            audition.destinationDetail = destinationDetail
            audition.sidesLink = sidesLink
            audition.castingNotes = resolvedCastingNotes
            audition.actorNotes = actorNotes
            audition.projectDetails = projectDetails
            audition.importantDates = importantDates.isEmpty ? nil : importantDates
            audition.roleBreakdowns = roleBreakdowns.isEmpty ? nil : roleBreakdowns
            audition.sideMaterials = sideMaterials.isEmpty ? nil : sideMaterials
            audition.sourceDocuments = sourceDocuments.isEmpty ? nil : sourceDocuments
            audition.noticeSources = noticeSources.isEmpty ? nil : noticeSources
            audition.fieldEvidence = fieldEvidence.isEmpty ? nil : fieldEvidence
            audition.submissionInstructions = submissionInstructions
            audition.resumeURL = includeResume ? resumeURL : nil
            return audition
        }
    }

    /// Asynchronous parsing pipeline: runs deterministic regex/anchor extraction first,
    /// then enriches with the on-device Foundation Model when supported on this iPhone.
    static func parseAsync(
        _ rawText: String,
        pages: [String] = [],
        sourceDocuments: [AuditionSource] = [],
        layoutDocument: LayoutDocument? = nil
    ) async -> Draft {
        let base = parse(rawText, pages: pages, sourceDocuments: sourceDocuments, layoutDocument: layoutDocument)
        var refined = await OnDeviceIntelligence.refineDraftWithFoundationModel(base, sourceText: rawText)
        let effectivePages = pages.isEmpty ? (layoutDocument?.reconstructedPages ?? []) : pages
        populateStructuredNoticeData(&refined, text: refined.sourceText, pages: effectivePages)
        return refined
    }

    static func parse(
        _ rawText: String,
        pages: [String] = [],
        sourceDocuments: [AuditionSource] = [],
        layoutDocument: LayoutDocument? = nil
    ) -> Draft {
        var d = Draft()
        let cleaned = ScriptParser.cleanPastedText(rawText)
        d.sourceText = cleaned
        d.sourceDocuments = sourceDocuments
        let effectivePages = pages.isEmpty ? (layoutDocument?.reconstructedPages ?? []) : pages

        // Pass 1 (Notice Extractor): Route multi-page packets through `DocumentPageRouter` so
        // cover notices, breakdown tables, and tail submission pages feed notice extraction within budget.
        let routed: RoutedDocument?
        if let layoutDocument {
            routed = DocumentPageRouter.route(layoutDocument, tokenBudget: 900)
        } else if !effectivePages.isEmpty {
            let layoutPages = effectivePages.enumerated().map { idx, pageText in
                PDFGeometryExtractor.syntheticLines(from: pageText, pageIndex: idx, preserveIndentation: true)
            }
            routed = DocumentPageRouter.route(
                LayoutDocument(pages: layoutPages, reconstructedPages: effectivePages),
                tokenBudget: 900
            )
        } else {
            routed = nil
        }

        let noticeSource: String
        if let routed, !routed.noticePages.isEmpty {
            noticeSource = routed.noticeTextSlice
        } else if !effectivePages.isEmpty {
            let isLongPacket = effectivePages.count >= 2 || rawText.count > 3500
            noticeSource = isLongPacket
                ? effectivePages.prefix(2).joined(separator: "\n\n")
                : cleaned
        } else {
            noticeSource = rawText.count > 3500 ? String(rawText.prefix(2500)) : cleaned
        }

        let text = tidy(noticeSource)
        let lower = text.lowercased()
        let noticeOnly = isNoticeOnly(cleaned)

        d.due = detectDate(in: text)
        var candidates = detectCandidateRoles(in: text)
        // If notice labels didn't have explicit roles, check if screenplay cues contain characters
        if candidates.isEmpty && !noticeOnly {
            candidates = ScriptParser.extractCharacters(from: cleaned)
        }
        d.candidateRoles = candidates
        if candidates.count == 1 && !containsOpenRoleChoice(in: text) {
            d.role = candidates[0]
            d.castingNotes = extractCharacterDescription(for: d.role, in: cleaned)
        } else {
            // When multiple roles are present, do not arbitrarily choose one:
            // leave it empty so the app explicitly asks the actor which role they are auditioning for.
            d.role = ""
        }
        if let project = detectProject(in: text) {
            d.project = project
        }
        // Detect explicit role size/tier from notice text
        let roleSizeLower = lower
        if roleSizeLower.contains("series regular") || roleSizeLower.contains("series lead") {
            d.roleSize = "Series Regular"
        } else if roleSizeLower.range(of: #"\bco[-\s]?star\b"#, options: .regularExpression) != nil {
            d.roleSize = "Co-Star"
        } else if roleSizeLower.contains("day player") {
            d.roleSize = "Day Player"
        } else if roleSizeLower.range(of: #"\bsupporting\b"#, options: .regularExpression) != nil {
            d.roleSize = "Supporting"
        } else if roleSizeLower.range(of: #"\b(?:lead|lead role|main role|principal role|feature role)\b"#, options: .regularExpression) != nil {
            d.roleSize = "Lead"
        } else if roleSizeLower.contains("principal") {
            d.roleSize = "Principal"
        }
        if let office = detectCastingOffice(in: text) {
            d.castingOffice = office
        }
        // Hierarchical Scene Portions (Pass 2 identification)
        let portions = noticeOnly ? [] : ScriptParser.identifyScenePortions(from: cleaned, pages: effectivePages)
        d.availablePortions = portions

        let targetRole = d.role.isEmpty ? (d.candidateRoles.first ?? "") : d.role
        let matchingIDs = portions.filter { $0.characters.contains { $0.caseInsensitiveCompare(targetRole) == .orderedSame } }.map(\.id)
        d.selectedPortionIDs = Set(matchingIDs.isEmpty ? portions.prefix(3).map(\.id) : matchingIDs)

        let parsedScenes = noticeOnly ? [] : ScriptParser.parseScenes(from: cleaned, myRole: d.role)
        if !parsedScenes.isEmpty {
            d.scenes = parsedScenes.count
        } else if !portions.isEmpty {
            d.scenes = d.selectedPortionIDs.isEmpty ? portions.count : d.selectedPortionIDs.count
        } else if noticeOnly {
            d.scenes = 0
        } else if let explicit = detectSceneCount(in: text) {
            d.scenes = max(explicit, 0)
        } else {
            d.scenes = 0
        }

        func ask(_ s: String) { if !d.asks.contains(s) { d.asks.append(s) } }
        // Contextual requirements: match actual instruction contexts rather than isolated screenplay dialogue words
        if firstMatch(#"(?i)\b(?:please\s+)?slate\s*(?:first|video|instructions?|clip|required)?\b|\binclude\s+(?:a\s+)?slate\b"#, in: text) != nil {
            ask("Slate first")
        }
        if firstMatch(#"(?i)\b(?:horizontal|landscape)\s+(?:mode|framing|orientation|video|format|shot)\b|\b(?:frame|shoot|record|film)\s+in\s+landscape\b|\bslate\s+first\s*,\s*landscape\b|\blandscape\s*,\s*full\s+length\b|\bhorizontal\s*\(landscape\)|\borientation\s*[:\-]\s*(?:horizontal|landscape)\b|\blandscape\s+only\b|\bhorizontal\s*/\s*landscape\b"#, in: text) != nil {
            ask("Landscape")
        }
        if firstMatch(#"(?i)\b(?:full[-\s]?body|head[-\s]?to[-\s]?toe)\s+(?:photo|picture|headshot)\b"#, in: text) != nil {
            ask("Headshots")
        }
        let fullBodyPattern = #"(?i)\b(?:full[-\s]?body|head[-\s]?to[-\s]?toe|full[-\s]?length)\s*(?:shot|slate|framing|video|view)\b"#
        let instructionLines = text.components(separatedBy: .newlines)
        if let bodyLineIndex = instructionLines.firstIndex(where: { firstMatch(fullBodyPattern, in: $0) != nil }) {
            let context = instructionLines.enumerated()
                .filter { abs($0.offset - bodyLineIndex) <= 1 }
                .map(\.element)
                .joined(separator: " ").lowercased()
            let explicitlySeparate = context.range(of: #"\bseparat(?:e|ely)\b[^.\n]{0,80}\b(?:video|clip|file)\b|\b(?:video|clip|file)\b[^.\n]{0,80}\bseparat(?:e|ely)\b"#, options: .regularExpression) != nil
            let includesSlate = !explicitlySeparate && (
                context.range(of: #"\b(?:slate|intro(?:duction)?)\b"#, options: .regularExpression) != nil
                    || context.range(of: #"\bname\b[^.\n]{0,80}\bheight\b|\bheight\b[^.\n]{0,80}\bname\b"#, options: .regularExpression) != nil
            )
            ask(includesSlate ? "Full-body shot with slate" : "Full-body shot")
            d.isFullBodyShotOptional = context.range(of: #"\b(?:optional|if available|not required)\b"#, options: .regularExpression) != nil
        }
        if firstMatch(#"(?i)\b(?:intro|introduction)\s+video\b|\bintroductory\s+video\b|\bintro\s+clip\b|\b(?:detailed|self[-\s]?|brief|short)\s+introduction\b"#, in: text) != nil {
            ask("Intro video")
        }
        if firstMatch(#"(?i)\bvideo\b[\s\S]{0,80}\b(?:self[\s-]?tape|introduction|intro)\b|\b(?:self[\s-]?tape|introduction|intro)\b[\s\S]{0,80}\bvideo\b"#, in: text) != nil {
            ask("Self-tape or introduction video")
        }
        if firstMatch(#"(?i)\b(?:headshots?|recent\s+photos?|recent\s+photographs?)\b|(?is)\b(?:send|attach|include|submit|mail|with|along\s+with)\b[\s\S]{0,60}?\b(?:pictures?|photos?)\b"#, in: text) != nil {
            ask("Headshots")
        }
        if firstMatch(#"(?i)(?:send(?:\s+in)?|include|attach|with|share|submit|your)[\s\S]{0,80}?\b(?:contact\s+(?:no\.?|number)|phone\s+number|mobile\s+(?:no\.?|number))\b|(?m)^\s*[•\-\*]\s*(?:contact\s+(?:no\.?|number)|phone\s+number|mobile\s+(?:no\.?|number))\b"#, in: text) != nil {
            ask("Contact number")
        }
        if firstMatch(#"(?i)\b(?:resume|résumé)\b[\s\S]{0,50}\b(?:optional|not\s+required|if\s+available)\b|\b(?:optional|not\s+required|if\s+available)\b[\s\S]{0,50}\b(?:resume|résumé)\b"#, in: text) != nil {
            ask("Resume (optional)")
        } else if firstMatch(#"(?i)\b(?:resume|résumé)\b"#, in: text) != nil {
            ask("Resume")
        }
        d.includeSlate = d.asks.contains { $0.localizedCaseInsensitiveContains("video") || $0.localizedCaseInsensitiveContains("slate") || $0.localizedCaseInsensitiveContains("intro") }
        d.includeHeadshots = d.asks.contains { $0.localizedCaseInsensitiveContains("headshot") || $0.localizedCaseInsensitiveContains("photo") }
        d.isSlateOptional = firstMatch(#"(?i)\b(?:slate|intro(?:duction)?\s+video|self-?tape)\b[^.\n]{0,50}\b(?:optional|if\s+available|not\s+required)\b|\b(?:optional|if\s+available|not\s+required)\b[^.\n]{0,50}\b(?:slate|intro(?:duction)?\s+video|self-?tape)\b"#, in: text) != nil
        d.isHeadshotOptional = firstMatch(#"(?i)\b(?:headshot|photo|photograph)\b[^.\n]{0,50}\b(?:optional|if\s+available|not\s+required)\b|\b(?:optional|if\s+available|not\s+required)\b[^.\n]{0,50}\b(?:headshot|photo|photograph)\b"#, in: text) != nil
        if let location = detectLocation(in: text) {
            ask("Location: \(location)")
        }
        if let email = firstMatch(#"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"#, in: text) {
            d.destinationDetail = email
            d.destination = .email
            d.destinationWasDetected = true
        }

        // Context-aware link classification: inspects the text and labels immediately before each URL
        // to distinguish whether a link is for uploading/submitting tapes vs downloading/reading script sides.
        let classified = detectClassifiedLinks(in: text)
        if let sidesLink = classified.sidesLink {
            d.sidesLink = sidesLink
            if sidesLink.contains("drive.google.com") {
                ask("Sides: Google Drive link")
            } else if sidesLink.contains("dropbox.com") {
                ask("Sides: Dropbox link")
            } else if sidesLink.contains("wetransfer.com") {
                ask("Sides: WeTransfer link")
            } else {
                ask("Sides link attached")
            }
        }
        if let subLink = classified.submissionLink {
            if d.destinationDetail == nil || d.destinationDetail?.contains("@") == false {
                d.destinationDetail = subLink
                d.destination = .emailOrLink
                d.destinationWasDetected = true
            }
        }
        if let minutes = detectLengthLimit(in: text) { ask("Under \(minutes) min") }

        // Detect WhatsApp submission (very common in Indian casting notices)
        if let waNumber = firstMatch(#"(?i)(?:whatsapp|wa\.me|send\s+on\s+whatsapp|submit\s+(?:on|via|to|through)\s+whatsapp)\s*(?:to\s*)?[:\-]?\s*(\+?[\d\s\-]{7,15})"#, in: text, options: .caseInsensitive) {
            let number = waNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if number.count >= 7 {
                d.destinationDetail = "+\(number)"
                d.destination = .emailOrLink
                d.destinationWasDetected = true
                ask("WhatsApp: +\(number)")
            }
        }
        // Detect WeTransfer submission
        if firstMatch(#"(?i)\bwetransfer\b"#, in: text) != nil {
            ask("WeTransfer upload")
        }
        // Detect Google Form
        if firstMatch(#"(?i)\bgoogle\s*form\b|forms\.gle\b|docs\.google\.com/forms\b"#, in: text) != nil {
            ask("Google Form")
        }
        // Detect pay/compensation mentions
        if let pay = firstMatch(#"(?i)\b(?:paid|stipend|honorarium|compensation|fee|per\s+day|day\s+rate|rate\s*[:\-]\s*[\$₹£€]?\d+)"#, in: text) {
            let _ = pay // just note it exists — set a flag to indicate paid project
            ask("Paid role")
        }
        // If no submission destination found yet, check for a plain phone number
        if d.destinationDetail == nil {
            if let phone = firstMatch(#"(?:call|contact|reach|send|submit|whatsapp|call\s+us|contact\s+us)\s*(?:at|on|to)?\s*[:\-]?\s*(\+?[\d\s\(\)\-]{7,18})"#, in: text, options: .caseInsensitive) {
                let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if digits.count >= 7 {
                    d.destinationDetail = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    ask("Call/WhatsApp: \(phone.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        // If notice says sides will be given at the audition, do not flag sides as missing
        if firstMatch(#"(?i)\b(?:sides\s+(?:will\s+be\s+provided|on\s+arrival|given\s+at|provided\s+at|to\s+be\s+provided|at\s+the\s+audition|sent\s+later|will\s+be\s+sent)|audition\s+sides\s+to\s+follow|scripts?\s+(?:will\s+be|to\s+be)\s+(?:provided|sent|given|shared))\b"#, in: text) != nil {
            d.sidesOnArrival = true
        }

        // Contextual project type
        if firstMatch(#"(?i)\b(?:short\s+film|short\s+format|short\s+movie)\b"#, in: text) != nil {
            d.projectType = "Short film"
        } else if firstMatch(#"(?i)\b(?:music\s+video|lyric\s+video|album\s+video)\b"#, in: text) != nil {
            d.projectType = "Music video"
        } else if firstMatch(#"(?i)\b(?:documentary|docuseries|docu-?series|doc\s+series)\b"#, in: text) != nil {
            d.projectType = "Documentary"
        } else if firstMatch(#"(?i)\b(?:web\s+series|ott\s+series|streaming\s+series|digital\s+series)\b"#, in: text) != nil {
            d.projectType = "Web series"
        } else if firstMatch(#"(?i)\b(?:reality\s+(?:show|series|tv)|reality\s+program)\b"#, in: text) != nil {
            d.projectType = "Reality show"
        } else if firstMatch(#"(?i)\b(?:ott\s+film|ott\s+original|streaming\s+film|direct-to-ott|direct\s+to\s+ott)\b"#, in: text) != nil {
            d.projectType = "OTT film"
        } else if firstMatch(#"(?i)\b(?:tv\s+ad|television\s+advertisement|brand\s+film|brand\s+video|product\s+video|social\s+media\s+ad|digital\s+ad|influencer)\b"#, in: text) != nil {
            d.projectType = "Brand content"
        } else if firstMatch(#"(?i)\b(?:feature\s+film|feature\s+length|theatrical\s+film|film\s+project|indie\s+film|cinema)\b"#, in: text) != nil {
            d.projectType = "Feature film"
        } else if firstMatch(#"(?i)\b(?:tv\s+series|television\s+series|web\s+series|limited\s+series|mini-?series|episodic|drama\s+series|comedy\s+series|pilot)\b"#, in: text) != nil {
            d.projectType = "Series"
        } else if firstMatch(#"(?i)\b(?:commercial|brand\s+campaign|tv\s+spot|ad\s+campaign|ad\s+film|promo)\b"#, in: text) != nil {
            d.projectType = "Commercial"
        } else if firstMatch(#"(?i)\b(?:stage\s+play|theatrical\s+production|theatre\s+play|broadway|musical\s+theatre|stage\s+production)\b"#, in: text) != nil {
            d.projectType = "Theatre"
        }

        // Industry platform destinations
        for dest in [Destination.actorsAccess, .backstage, .castingNetworks, .spotlight] {
            if lower.contains(dest.rawValue.lowercased()) {
                d.destination = dest
                d.destinationWasDetected = true
                ask(dest.rawValue)
                break
            }
        }
        // Extract director/character notes for guidance (prioritizing actionable notes over generic announcements)
        let guidanceRole = d.role.isEmpty ? (d.candidateRoles.first ?? "") : d.role
        if !guidanceRole.isEmpty, let roleNote = extractCharacterDescription(for: guidanceRole, in: cleaned), isValidGuidance(roleNote) {
            d.aiGuidance = roleNote
        }

        if d.aiGuidance.isEmpty {
            let guidancePatterns = [
                // Director note / what I'm looking for / acting notes
                #"(?i)(?:director(?:['’]s)?\s*notes?|what\s+i(?:['’]m)?\s+looking\s+for|what\s+i\s+need\s+to\s+see|acting\s+notes?|tone\s+notes?)[:\-]?\s*([^\n]+(?:\n(?!\s*(?:SLATE|THE\s+SIDE|SIDE\s+[A-Z0-9]|SCENE|INT\.|EXT\.|AUDITION|\z))[^\n]+)*)"#,
                // How to use these sides / sides instructions / dialogue sides notes
                #"(?i)(?:how\s+to\s+use\s+these\s+sides|sides?\s+instructions?|dialogue\s+sides?\s*\([^)]*\))[:\-]?\s*([^\n]+(?:\n(?!\s*(?:THE\s+CHARACTERS|SLATE|SIDE|\z))[^\n]+)*)"#,
                // Notes on casting
                #"(?i)(?:notes?\s+on\s+casting|casting\s+notes?)[:\-]?\s*([^\n]+(?:\n(?!\s*(?:Audition\s+Dates|Submissions?|\z))[^\n]+)*)"#,
                // Character brief / role description (NOT generic project description)
                #"(?i)(?:character\s+(?:note|brief|description|background|overview)|about\s+the\s+(?:role|character)|role\s+(?:description|brief|overview))[:\-]?\s*\n?([^\n]+(?:\n(?!\s*(?:AUDITION|SUBMISSION|DATE|\z))[^\n]+)*)"#
            ]
            for pattern in guidancePatterns {
                if let note = firstMatch(pattern, in: text, options: .caseInsensitive) {
                    let trimmed = clean(note).trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 20 && isValidGuidance(trimmed) {
                        d.aiGuidance = trimmed
                        break
                    }
                }
            }
        }
        populateStructuredNoticeData(&d, text: cleaned, pages: effectivePages)
        return d
    }
}
