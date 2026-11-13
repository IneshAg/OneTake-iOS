import Foundation
import UIKit

extension NoticeParser {
    /// Adds a structured, source-aware layer over the rule-based notice and sides extraction.
    /// The raw text remains available for review; this layer records only fields grounded in it.
    static func populateStructuredNoticeData(_ draft: inout Draft, text: String, pages: [String]) {
        draft.fieldEvidence = []
        let sourcePages = pages.isEmpty ? [text] : pages
        if draft.sourceDocuments.isEmpty {
            draft.sourceDocuments = [AuditionSource(name: "Pasted or imported notice", kind: .castingNotice, pageCount: sourcePages.count)]
        }
        draft.noticeSources = sourcePages.enumerated().map { index, page in
            let lower = page.lowercased()
            let looksLikeSides = !ScriptParser.extractCharacters(from: page).isEmpty ||
                lower.contains("audition sides") || lower.contains("script sides")
            let kind: AuditionSourceKind = looksLikeSides ? .scriptSides : .castingNotice
            let parent = draft.sourceDocuments.first(where: { doc in
                let start = (doc.pageNumber ?? 1)
                let end = start + max((doc.pageCount ?? 1) - 1, 0)
                return (start...end).contains(index + 1)
            })
            return AuditionSource(name: "\(parent?.name ?? "Imported document") · page \(index + 1)", kind: kind, url: parent?.url, pageNumber: index + 1, pageCount: 1, parentSourceID: parent?.id)
        }

        let synopsis = firstMatch(
            #"(?is)(?:about\s+the\s+project|project\s+synopsis|synopsis)(?:\s*:\s*|\s+)(.+?)(?=\n\s*(?:character\s+breakdowns?|note\s+on\s+casting|production\s+schedule|production\s+information|audition\s+dates|audition\s+requirements|submission|casting\s+team)\b|\z)"#,
            in: text
        ).map { clean($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let payLine = lines.first { line in
            let lower = line.lowercased()
            if lower.contains("pay attention") || lower.contains("pay me back") || lower.contains("pay you back") || lower.contains("pay them back") {
                return false
            }
            return line.range(of: #"(?i)\b(?:paid|stipend|salary|rate of pay|day rate|hourly rate|compensation|honorarium|per\s+diem|deferred\s+pay|union\s+scale|scale\s+rate|unpaid)\b|(?i)\bpay\s*[:\-]\s*|\bpay\s+is\s+|\bpay\s+rate\b"#, options: .regularExpression) != nil
        }
        let unionLine = lines.first { $0.range(of: #"(?i)\b(?:SAG[- ]?AFTRA|AEA|Equity|non[- ]union|nonunion|union contract|no union contract)\b"#, options: .regularExpression) != nil }
        let ndaLine = lines.first { $0.range(of: #"(?i)\bNDA\b|non[- ]disclosure agreement"#, options: .regularExpression) != nil }
        let travelLine = lines.first { $0.range(of: #"(?i)\b(?:travel|travel expenses|accommodation|lodging|per diem|relocation)\b"#, options: .regularExpression) != nil }
        let existingDetails = draft.projectDetails
        draft.projectDetails = AuditionProjectDetails(
            synopsis: (synopsis?.isEmpty == false ? synopsis : nil) ?? existingDetails?.synopsis,
            productionCompany: labeled(["production company", "produced by"], in: text) ?? existingDetails?.productionCompany,
            producer: labeled(["producer"], in: text) ?? existingDetails?.producer,
            director: labeled(["director"], in: text) ?? existingDetails?.director,
            payTerms: payLine ?? existingDetails?.payTerms,
            unionStatus: unionLine ?? existingDetails?.unionStatus,
            ndaNotes: ndaLine ?? existingDetails?.ndaNotes,
            castingArea: detectLocation(in: text) ?? existingDetails?.castingArea,
            productionLocation: labeled(["production location", "filming location", "location"], in: text) ?? existingDetails?.productionLocation,
            travelNotes: travelLine ?? existingDetails?.travelNotes
        )

        var extractedDates = extractImportantDates(in: draft.sourceText, pages: sourcePages, sources: draft.noticeSources)
        for date in draft.importantDates {
            if !extractedDates.contains(where: { $0.kind == date.kind }) {
                extractedDates.append(date)
            }
        }
        draft.importantDates = extractedDates
        draft.roleBreakdowns = draft.candidateRoles.map { role in
            let description = extractCharacterDescription(for: role, in: draft.sourceText)
            let age = description.flatMap { firstMatch(#"(?i)\b(?:early\s+|mid[- ]|late\s+)?\d{1,2}\s*(?:-|–|to)\s*\d{1,2}\b|\b(?:early|mid|late)\s+\d{1,2}s?\b|\b\d{1,2}s\b"#, in: $0) }
            let gender = description.flatMap { firstMatch(#"(?i)\b(?:female|male|woman|man|girl|boy|non[- ]binary|femme|F|M|NB)\b"#, in: $0) }
            return AuditionRoleBreakdown(
                name: role,
                description: description,
                ageRange: age,
                gender: gender,
                ethnicity: nil,
                skills: [],
                eligibilityNotes: description
            )
        }

        var materials: [AuditionSideMaterial] = []
        for portion in draft.availablePortions {
            let sideNumber = firstMatch(#"(?i)\bside\s*#?\s*([A-Z0-9]+)\b"#, in: portion.heading)
                ?? firstMatch(#"(?i)\bside\s*#?\s*([A-Z0-9]+)\b"#, in: portion.rawText)
            let material = AuditionSideMaterial(
                title: portion.displayTitle,
                roleName: portion.characters.count == 1 ? portion.characters.first : nil,
                sideNumber: sideNumber,
                pageStart: portion.pageNumber,
                sourceID: portion.pageNumber.flatMap { page in draft.noticeSources.first(where: { $0.pageNumber == page })?.id },
                text: portion.rawText
            )
            materials.append(material)
            for character in portion.characters {
                if let roleIndex = draft.roleBreakdowns.firstIndex(where: { $0.name.caseInsensitiveCompare(character) == .orderedSame }) {
                    draft.roleBreakdowns[roleIndex].sideMaterialIDs.append(material.id)
                }
            }
        }
        draft.sideMaterials = materials

        var instructions = draft.submissionInstructions ?? AuditionSubmissionInstructions()
        if instructions.slateRequirements.isEmpty {
            instructions.slateRequirements = lines.filter { $0.localizedCaseInsensitiveContains("slate") }
        }
        if instructions.videoOrientation == nil {
            if text.range(of: #"(?i)\b(?:horizontal|landscape)\b"#, options: .regularExpression) != nil { instructions.videoOrientation = "Landscape" }
            else if text.range(of: #"(?i)\b(?:vertical|portrait)\b"#, options: .regularExpression) != nil { instructions.videoOrientation = "Portrait" }
        }
        if instructions.acceptedFormats.isEmpty {
            instructions.acceptedFormats = ["mp4", "mov", "m4v"].filter { format in
                text.range(of: #"(?i)\.\s*"# + format + #"\b|\b"# + format + #"\s+(?:format|file)"#, options: .regularExpression) != nil
            }
        }
        if instructions.requiredVideoCount == nil {
            instructions.requiredVideoCount = firstMatch(#"(?i)\b(?:record|submit|send|upload)\s+(?:exactly\s+)?(\d{1,2}|one|two|three|four)\s+(?:separate\s+)?videos?\b"#, in: text).flatMap(parseSmallNumber)
        }
        if instructions.maxTakes == nil {
            instructions.maxTakes = firstMatch(#"(?i)\b(?:maximum|max|up to|no more than)\s+(\d{1,2})\s+takes?\b"#, in: text).flatMap(Int.init)
        }
        let filename = detectFileNamingInstruction(in: text)
        if instructions.fileNamingRule == nil {
            instructions.fileNamingRule = filename.rule
        }
        if instructions.fileNameTemplate == nil {
            instructions.fileNameTemplate = filename.template
        }
        if instructions.submissionRouteNotes == nil {
            instructions.submissionRouteNotes = lines.first { $0.range(of: #"(?i)\b(?:submit|upload|email|send|share)\b"#, options: .regularExpression) != nil }
        }
        instructions.otherRequirements = draft.asks
        draft.submissionInstructions = instructions

        func addEvidence(field: String, value: String) {
            guard !value.isEmpty,
                  let pageIndex = sourcePages.firstIndex(where: { $0.range(of: value, options: .caseInsensitive) != nil }),
                  draft.noticeSources.indices.contains(pageIndex) else { return }
            let nsText = sourcePages[pageIndex] as NSString
            let match = nsText.range(of: value, options: .caseInsensitive)
            guard match.location != NSNotFound else { return }
            let excerptRange = NSRange(location: max(0, match.location - 80), length: min(nsText.length - max(0, match.location - 80), match.length + 180))
            draft.fieldEvidence.append(AuditionFieldEvidence(
                field: field,
                sourceID: draft.noticeSources[pageIndex].id,
                pageNumber: pageIndex + 1,
                excerpt: nsText.substring(with: excerptRange).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        if !draft.project.isEmpty { addEvidence(field: "project", value: draft.project) }
        if !draft.castingOffice.isEmpty { addEvidence(field: "castingOffice", value: draft.castingOffice) }
        if !draft.role.isEmpty { addEvidence(field: "role", value: draft.role) }
        for date in draft.importantDates {
            if let sourceText = date.sourceText { addEvidence(field: "date.\(date.kind.rawValue)", value: sourceText) }
        }
    }

    static func parseSmallNumber(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        return ["one": 1, "two": 2, "three": 3, "four": 4][value.lowercased()]
    }

    static func detectFileNamingInstruction(in text: String) -> (rule: String?, template: String?) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines where line.range(of: #"(?i)\b(?:file\s*name|filename|name\s+(?:each\s+|all\s+)?files?|label\s+(?:each\s+|all\s+)?files?)\b"#, options: .regularExpression) != nil {
            let templatePattern = #"(?i)(?:format|as|like|e\.g\.|e\.g|:|with)\s*[\"']?([A-Za-z][A-Za-z0-9{}#._-]*(?:[._-][A-Za-z0-9{}#._-]+){1,})"#
            let template = firstMatch(templatePattern, in: line).map(normalizeFileNameTemplate)
            if template != nil { return (line, template) }
            if line.localizedCaseInsensitiveContains("side #") || line.localizedCaseInsensitiveContains("side number") {
                return (line, "{name}_SIDE_{side}")
            }
            if line.localizedCaseInsensitiveContains("full name") {
                return (line, "{name}")
            }
            return (line, nil)
        }
        return (nil, nil)
    }

    static func normalizeFileNameTemplate(_ raw: String) -> String {
        var template = raw
        let replacements: [(String, String)] = [
            (#"(?i)first[ _-]?name"#, "{firstName}"),
            (#"(?i)last[ _-]?name"#, "{lastName}"),
            (#"(?i)(?:actor|performer|full)[ _-]?name|\bname\b"#, "{name}"),
            (#"(?i)role|character"#, "{role}"),
            (#"(?i)project|production|job"#, "{project}"),
            (#"(?i)side\s*#?"#, "{side}"),
            (#"(?i)scene"#, "{scene}"),
            (#"(?i)take"#, "{take}"),
            (#"(?i)song\s*title"#, "{song}")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            template = regex.stringByReplacingMatches(in: template, range: NSRange(template.startIndex..., in: template), withTemplate: replacement)
        }
        return template
    }

    static func extractImportantDates(in text: String, pages: [String], sources: [AuditionSource]) -> [AuditionDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var dates: [AuditionDate] = []
        for match in matches {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let lineRange = text.lineRange(for: range)
            let context = String(text[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = context.lowercased()
            let hasDateContext = ["deadline", "due", "submit", "submission", "callback", "recall", "rehearsal", "audition", "dance call", "vocal call", "performance", "opening", "closing", "show date", "production", "filming", "shoot", "schedule", "dates"].contains(where: lower.contains)
            guard hasDateContext else { continue }
            let kind: AuditionDateKind
            if ["deadline", "due", "submit by", "submission", "accepted until", "tape due"].contains(where: lower.contains) {
                kind = .submissionDeadline
            } else if lower.contains("callback") || lower.contains("recall") {
                kind = .callback
            } else if lower.contains("rehearsal") {
                let priorSameLine = dates.filter { $0.label == context && $0.kind == .rehearsalStart }.count
                kind = priorSameLine == 0 ? .rehearsalStart : .rehearsalEnd
            } else if lower.contains("audition") || lower.contains("dance call") || lower.contains("vocal call") {
                kind = .audition
            } else if lower.contains("performance") || lower.contains("opening") || lower.contains("show date") {
                kind = lower.contains("closing") || lower.contains("last performance") ? .performanceEnd : .performanceStart
            } else if lower.contains("production") || lower.contains("filming") || lower.contains("shoot") {
                let priorSameLine = dates.filter { $0.label == context && $0.kind == .productionStart }.count
                kind = lower.contains("wrap") || lower.contains("end") || priorSameLine > 0 ? .productionEnd : .productionStart
            } else if lower.contains("rehearsal") {
                kind = .rehearsalEnd
            } else {
                kind = .other
            }
            let dateText = String(text[range])
            let pageIndex = pages.firstIndex { $0.range(of: dateText, options: .caseInsensitive) != nil }
            let source = pageIndex.flatMap { sources.indices.contains($0) ? sources[$0] : nil }
            dates.append(AuditionDate(kind: kind, date: date, label: context, sourceID: source?.id, pageNumber: source?.pageNumber, sourceText: String(text[range])))
        }
        return dates
    }

    /// A casting notice that says the actor may choose a character must not be converted into an
    /// arbitrary role selection, even if OCR happened to find only one role on the notice page.
    static func containsOpenRoleChoice(in text: String) -> Bool {
        firstMatch(#"(?i)\b(?:your choice|role of your choice|character of your choice|any character|choose (?:a|any) character|character you(?:'|’)d like to read|role you(?:'|’)d like to read)\b"#, in: text) != nil
    }

    /// Verifies that an extracted guidance block contains genuine director/actor instructions,
    /// rejecting company PR, boilerplate audition announcements, and generic synopses.
    static func isValidGuidance(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("holding audition") || lower.contains("holds audition") || lower.contains("holding a casting call") {
            return false
        }
        if lower.contains("submissions will be accepted") || lower.contains("in-person auditions will be held") {
            return false
        }
        if lower.contains("for the world premiere production") {
            return false
        }
        if lower.contains("the shattered glass project") {
            return false
        }
        return true
    }

    /// Detects browser tab headers, repo paths, or window status chrome captured when scanning screen displays
    static func isNoiseLine(_ line: String) -> Bool {
        let trimmed = clean(line)
        if trimmed.isEmpty { return false }
        // Browser tab / window chrome: e.g. "• - 100 Days Of Sv X Ineshag/Onetal X * History."
        if trimmed.contains(" X ") || trimmed.contains(" x ") || trimmed.contains(" • ") || trimmed.hasPrefix("• -") || trimmed.hasPrefix("- •") {
            if trimmed.contains("History") || trimmed.contains("/") || trimmed.contains("*") || trimmed.contains("Days Of") || trimmed.contains("localhost") {
                return true
            }
        }
        if trimmed.range(of: #"(?i)\b(?:github\.com|localhost|chrome|safari|firefox)\b"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[•\-\*\s]+[0-9]+\s+Days\s+Of\b"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"[A-Za-z0-9_\-]+/[A-Za-z0-9_\-]+\s+X\s+\*"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Normalises OCR output: unified quotes/dashes/newlines, no zero-width characters, strips display chrome noise.
    static func tidy(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "\u{200B}", with: "")
        let filteredLines = normalized.components(separatedBy: .newlines).filter { !isNoiseLine($0) }
        return filteredLines.joined(separator: "\n")
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let g = (group < match.numberOfRanges) ? group : (match.numberOfRanges > 0 ? 0 : -1)
        guard g >= 0, match.range(at: g).location != NSNotFound,
              let r = Range(match.range(at: g), in: text) else { return nil }
        return String(text[r])
    }

    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'*_.,;:-#“"))
    }

    /// "Role: Maya", "Project - The Last Summer" — a label at the start of a line, then its value.
    static func labeled(_ labels: [String], in text: String) -> String? {
        for label in labels {
            let pattern = #"^[\s>*•\-]*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*[:\-]\s*(.+)$"#
            if let value = firstMatch(pattern, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
                let cleaned = clean(value)
                if !cleaned.isEmpty, cleaned.count <= 150 { return cleaned }
            }
        }
        return nil
    }

    /// Prefers a date near "due / deadline / submit / by" over non-submission dates.
    /// Never falls back to arbitrary dates (such as shoot dates, publication dates, or birthdays).
    static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // OCR often drops the punctuation around times in lines such as
        // “Video submissions will be accepted until 11:59 pm on December 6, 2026”.
        // Anchor on that explicit submission wording before scanning other event dates.
        let acceptedUntilPattern = #"(?i)\b(?:video|self[- ]?tape|tape)\s+submissions?\s+(?:will\s+be\s+)?accepted\s+(?:until|through)\s+(?:(?:by|at)\s+)?(?:(\d{1,2}(?::\d{2})?\s*(?:[ap]\.?m\.?))(?:\s+([A-Z]{2,4}))?\s+(?:on\s+)?)?([A-Z][a-z]+\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4})(?:\s+(?:at|by|,)\s+(\d{1,2}(?::\d{2})?\s*(?:[ap]\.?m\.?))(?:\s+([A-Z]{2,4}))?)?"#
        if let regex = try? NSRegularExpression(pattern: acceptedUntilPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            func groupStr(_ index: Int) -> String? {
                guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound,
                      let r = Range(match.range(at: index), in: text) else { return nil }
                return String(text[r])
            }
            let timeStr = groupStr(1) ?? groupStr(4)
            let tzStr = groupStr(2) ?? groupStr(5)
            if let rawDateStr = groupStr(3) {
                var timeZone: TimeZone = .current
                if let tz = tzStr?.uppercased() {
                    let tzAliases: [String: String] = [
                        "ET": "America/New_York",
                        "EDT": "America/New_York",
                        "EST": "America/New_York",
                        "CT": "America/Chicago",
                        "CDT": "America/Chicago",
                        "CST": "America/Chicago",
                        "MT": "America/Denver",
                        "MDT": "America/Denver",
                        "MST": "America/Denver",
                        "PT": "America/Los_Angeles",
                        "PDT": "America/Los_Angeles",
                        "PST": "America/Los_Angeles"
                    ]
                    if let id = tzAliases[tz], let mappedTZ = TimeZone(identifier: id) {
                        timeZone = mappedTZ
                    } else if let parsedTZ = TimeZone(abbreviation: tz) {
                        timeZone = parsedTZ
                    }
                }
                let cleanDate = rawDateStr.replacingOccurrences(
                    of: #"(?i)(\d)(st|nd|rd|th)\b"#,
                    with: "$1",
                    options: .regularExpression
                ).replacingOccurrences(of: ",", with: "")

                if var time = timeStr {
                    time = time.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
                    let formats = [
                        "h:mm a MMMM d yyyy",
                        "h a MMMM d yyyy",
                        "h:mma MMMM d yyyy",
                        "ha MMMM d yyyy",
                        "h:mm a MMM d yyyy",
                        "h a MMM d yyyy",
                        "h:mma MMM d yyyy",
                        "ha MMM d yyyy"
                    ]
                    let dtStr = "\(time) \(cleanDate)"
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = timeZone
                    for f in formats {
                        formatter.dateFormat = f
                        if let d = formatter.date(from: dtStr) {
                            return d
                        }
                    }
                }

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = "MMMM d yyyy"
                if let d = formatter.date(from: cleanDate) { return d }
                formatter.dateFormat = "MMM d yyyy"
                if let d = formatter.date(from: cleanDate) { return d }
            }
        }
        let submissionKeywords = [
            "due", "deadline", "submit by", "submit before", "submission deadline", "tape due",
            "self-tape due", "send tape by", "send submissions by", "no later than", "submissions due",
            "due date", "submit no later", "turn in by",
            "accepted until", "submissions will be accepted", "video submissions", "accepted through",
            "submissions accepted", "submit your tape by", "submit by", "last day to submit",
            "last day to apply", "accept submissions until", "close on", "closes on"
        ]
        let nonDueKeywords = [
            "shoot", "shooting", "filming", "production", "principal photography", "rehearsal",
            "callback", "callbacks", "born", "birthday", "posted", "published", "notice date"
        ]

        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let line = text.lineRange(for: r)
            let context = text[line].lowercased()
            // Skip dates in lines explicitly about filming/shooting/callbacks unless explicitly about tape deadline
            if nonDueKeywords.contains(where: { context.contains($0) }) && !context.contains("tape") && !context.contains("audition") && !context.contains("due") {
                continue
            }
            if submissionKeywords.contains(where: { context.contains($0) }) {
                // NSDataDetector has a quirk where "due by November 5" can offset the parsed date.
                // Strip the preposition and evaluate the date substring directly when available.
                let matchedSub = String(text[r])
                if let stripped = firstMatch(#"(?i)(?:due\s+by|due|by|before|on|until)\s+([A-Za-z0-9,\s]+)"#, in: matchedSub) {
                    if let refinedMatch = detector.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)).first, let refinedDate = refinedMatch.date {
                        return refinedDate
                    }
                }
                if let d = match.date { return d }
            }
        }

        // Secondary pass: pick the earliest date mentioned in lines about auditions/submissions
        // when no explicit "due"/"deadline" keyword is present (e.g. "Auditions: December 7, 2026").
        var auditionDates: [Date] = []
        for match in matches {
            guard let r = Range(match.range, in: text), let d = match.date else { continue }
            let line = text.lineRange(for: r)
            let context = text[line].lowercased()
            // Skip scheduling/non-submission lines (rehearsals, callbacks, opening/closing)
            let scheduleOnly = ["rehearsal", "callback", "opening", "closing", "tech", "strike", "load-in", "meet & greet"]
            if scheduleOnly.contains(where: { context.contains($0) }) { continue }
            if context.contains("audition") || context.contains("submission") || context.contains("video") || context.contains("accepted") {
                auditionDates.append(d)
            }
        }
        if let earliest = auditionDates.min() { return earliest }

        // Support day-first formats like "5 November 2026" or "5th Nov 2026"
        let dayFirstPattern = #"(?i)\b(?:deadline|due date|submission deadline|last date to apply|submit(?:ting)? by|tape due|self-tape due(?: by)?|due by|due)\s*[:\-]?\s*(\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]+\s+\d{4})\b"#
        if let value = firstMatch(dayFirstPattern, in: text) {
            let normalized = value.replacingOccurrences(
                of: #"(?i)(\d)(st|nd|rd|th)\b"#,
                with: "$1",
                options: .regularExpression
            ).replacingOccurrences(of: ",", with: "")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMMM yyyy"
            if let d = formatter.date(from: normalized) { return d }
            formatter.dateFormat = "d MMM yyyy"
            if let d = formatter.date(from: normalized) { return d }
        }

        // NSDataDetector can miss dates copied from HTML where the label and date are
        // separated by non-breaking spaces or punctuation.
        let labeledDatePattern = #"(?i)\b(?:deadline|due date|submission deadline|submit(?:ting)? by|tape due|self-tape due(?: by)?|due by|due)\s*[:\-]?\s*([A-Z][a-z]+ \d{1,2}(?:st|nd|rd|th)?,? \d{4})\b"#
        guard let value = firstMatch(labeledDatePattern, in: text) else { return nil }
        let normalized = value.replacingOccurrences(
            of: #"(?i)(\d)(st|nd|rd|th)\b"#,
            with: "$1",
            options: .regularExpression
        ).replacingOccurrences(of: ",", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d yyyy"
        return formatter.date(from: normalized)
    }

    /// Detects if a scene is marked optional or secondary in casting instructions or script headers.
    /// E.g. "Scene 2 (optional)", "Scene 2: prepare if time permits", "Callback scene (optional)"
    static func isSceneOptional(scene: ScriptScene, in text: String) -> Bool {
        let t = scene.title.lowercased()
        let h = scene.heading.lowercased()
        if t.contains("optional") || h.contains("optional") { return true }
        if t.contains("if time permits") || h.contains("if time permits") { return true }

        let escapedTitle = NSRegularExpression.escapedPattern(for: scene.title)
        let patterns = [
            #"(?i)\b(?:scene\s*"# + "\(scene.number)" + #"\b|"# + escapedTitle + #")[^.\n\r]*\b(optional|if time permits|callback only|not required)\b"#,
            #"(?i)\b(optional|if time permits|callback only|not required)\b[^.\n\r]*\b(?:scene\s*"# + "\(scene.number)" + #"\b|"# + escapedTitle + #")"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    /// Extracts character breakdown demographics and director notes for a specific role from sides or notice text.
    /// E.g.: "NOOR · She/her · Early 60s · Afghan American" + "Director note: What I'm looking for..."
    static func extractCharacterDescription(for role: String, in text: String) -> String? {
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let escapedRole = NSRegularExpression.escapedPattern(for: trimmedRole)
        let lines = text.components(separatedBy: .newlines)

        // Narrative character profiles may have no label or line break after the
        // name. Keep the complete profile, stopping at the next notice section.
        let prosePattern = #"(?is)\b"# + escapedRole + #"\s+is\s+(a|an)\s+(.+?)(?=\s+(?:what\s+to\s+submit|actors?\s+should\s+email|submission\s+(?:details|instructions?)|audition\s+dates?|deadline)\b|\z)"#
        if let regex = try? NSRegularExpression(pattern: prosePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let articleRange = Range(match.range(at: 1), in: text),
           let descriptionRange = Range(match.range(at: 2), in: text) {
            let article = String(text[articleRange])
            let details = String(text[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let description = clean("\(trimmedRole) is \(article) \(details)")
            if description.count > trimmedRole.count + 10 {
                return description.trimmingCharacters(in: CharacterSet(charactersIn: " .\n\r\t"))
            }
        }

        var headerLine: String?
        var headerIndex: Int?

        // 1. Look for a role header line with breakdown/demographics:
        for (idx, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard let regex = try? NSRegularExpression(pattern: #"^\s*"# + escapedRole + #"\b\s*[·—\-:]\s*(.+)$"#, options: .caseInsensitive),
                  let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: trimmedLine) else { continue }

            let rest = String(trimmedLine[r]).trimmingCharacters(in: .whitespaces)
            if (try? NSRegularExpression(pattern: #"^(?:page|p\.)\s*\d+$"#, options: .caseInsensitive))?.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) != nil {
                continue
            }
            headerLine = trimmedLine
            headerIndex = idx
            break
        }

        // Fallback: check if role name appears on its own line followed immediately by demographics
        if headerLine == nil {
            for (idx, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.caseInsensitiveCompare(trimmedRole) == .orderedSame, idx + 1 < lines.count {
                    let nextLine = lines[idx + 1].trimmingCharacters(in: .whitespaces)
                    if (try? NSRegularExpression(pattern: #"^(?:she/her|he/him|they/them|\d{1,2}s?|age|female|male|non-binary)\b"#, options: .caseInsensitive))?.firstMatch(in: nextLine, range: NSRange(nextLine.startIndex..., in: nextLine)) != nil {
                        headerLine = "\(trimmedLine) · \(nextLine)"
                        headerIndex = idx + 1
                        break
                    }
                }
            }
        }

        // 2. Look for director's note or character description following the header line
        var directorNote: String?
        if let hIdx = headerIndex {
            let maxIdx = min(lines.count, hIdx + 30)
            let subsequent = lines[(hIdx + 1)..<maxIdx].joined(separator: "\n")
            let notePattern = #"(?i)\b(?:director(?:['’]s)?\s*note|character\s*note|note)\s*[:\-]\s*([^\n]+(?:\n(?!\s*(?:SLATE|THE\s+SIDE|SIDE\s+[A-Z]|SCENE|INT\.|EXT\.|[A-Z]{3,}\s*[·—\-:]))[^\n]+)*)"#
            if let regex = try? NSRegularExpression(pattern: notePattern, options: []),
               let match = regex.firstMatch(in: subsequent, range: NSRange(subsequent.startIndex..., in: subsequent)),
               let r = Range(match.range, in: subsequent) {
                directorNote = String(subsequent[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 3. Fallback for general casting notice format:
        if headerLine == nil && directorNote == nil {
            let generalPattern = #"(?im)^\s*"# + escapedRole + #"\s*[:\-]\s*([^\n]+(?:\n(?!\s*(?:[A-Z]{3,}\b|SCENE|DEADLINE|AUDITION))[^\n]+){0,4})"#
            if let regex = try? NSRegularExpression(pattern: generalPattern, options: []),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range, in: text) {
                let candidate = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.lowercased().contains("page ") {
                    return candidate
                }
            }
        }

        // 4. Structured notice "REQUIREMENT:" block when no per-character line matched
        if headerLine == nil && directorNote == nil && NoticeParser.isNoticeOnly(text) {
            var reqLines: [String] = []
            if let reqBlock = firstMatch(#"(?is)\brequirements?\s*[:\-]?\s*\n(.+?)(?=\n\s*(?:kindly\s+send|send\s+in|what\s+to\s+submit|submission|how\s+to\s+apply|note:|deadline)\b|\z)"#, in: text) {
                for rawLine in reqBlock.components(separatedBy: .newlines) {
                    let trimmed = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "•*- \t\r"))
                    guard !trimmed.isEmpty, !trimmed.contains("@"),
                          trimmed.range(of: #"(?i)^(?:mc\s|studio|commercials|mukesh\s+chh)"#, options: .regularExpression) == nil else { continue }
                    reqLines.append(trimmed)
                }
            }
            if let basedIn = firstMatch(#"(?i)\bbased\s+in\s+([A-Za-z]{2,24})\b"#, in: text) {
                let loc = "Based in \(basedIn.capitalized)"
                if !reqLines.contains(where: { $0.localizedCaseInsensitiveContains(basedIn) }) {
                    reqLines.append(loc)
                }
            }
            if !reqLines.isEmpty {
                return reqLines.joined(separator: " · ")
            }
        }

        var parts: [String] = []
        if let h = headerLine, !h.isEmpty { parts.append(h) }
        if let note = directorNote, !note.isEmpty { parts.append(note) }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

}
