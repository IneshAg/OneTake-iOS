import Foundation
import UIKit

extension NoticeParser {
    /// Detects all candidate roles mentioned in a casting notice, prioritizing explicit roles, industry tiers, and demographic breakdowns.
    static func detectCandidateRoles(in text: String) -> [String] {
        var roles: [String] = []

        let invalidRoleNames: Set<String> = [
            "multiple roles", "multiple role", "each character", "separate video", "a separate video",
            "all roles", "any role", "both roles", "various roles", "other characters", "the role",
            "your role", "this role", "character", "cast", "setting", "settings", "director note", "slate instruction",
            "what to submit", "submission requirements", "audition requirements", "requirements", "role details", "character details",
            "how to use these sides", "casting sides", "audition sides", "dialogue sides", "sides",
            "female identifying", "male identifying", "for female identifying", "for male identifying", "for any gender", "any gender",
            "your choice", "character of your choice", "the character of your choice", "a character of your choice"
        ]

        func addRole(_ r: String) {
            let cleaned = clean(r)
            guard !cleaned.isEmpty, !roles.contains(cleaned) else { return }
            let lower = cleaned.lowercased()
            guard !invalidRoleNames.contains(lower) else { return }
            let base = cleaned.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? cleaned
            if base.lowercased() != "male" && base.lowercased() != "female" {
                guard !ScriptParser.isBlacklistedNoticeWord(base) else { return }
            }
            roles.append(cleaned)
        }

        // Prose character profiles often have no "Role:" label or breakdown heading.
        // Example: "Alice is a 12–13-year-old girl who is introverted ...".
        let proseCharacterPattern = #"(?i)\b([A-Z][A-Za-z'’\-]{1,24})\s+is\s+(?:a|an)\s+(?:\d{1,2}\s*[-–]\s*\d{1,2}[- ]year[- ]old\s+)?(?:girl|boy|woman|man|child|teenager|teen|person)\b"#
        if let regex = try? NSRegularExpression(pattern: proseCharacterPattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    addRole(String(text[range]))
                }
            }
        }

        // 0. Audition sides page breakdown table (e.g. Grease style breakdown)
        let bdPattern = #"(?is)(?:Audition\s+Sides\s+Page\s+Breakdown|Sides\s+Page\s+Breakdown|Sides\s+Breakdown)\s*[:\n](.*?)(?=\n\s*\d+\s*\n|\n==|\z)"#
        if let regex = try? NSRegularExpression(pattern: bdPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let block = text[range]
            for line in block.components(separatedBy: .newlines) {
                let trimmed = clean(line)
                if trimmed.isEmpty || trimmed.lowercased().contains("please familiarise") { continue }
                let charSection: String
                if let actRange = trimmed.range(of: #"\bACT\b"#, options: [.caseInsensitive, .regularExpression]) {
                    charSection = String(trimmed[..<actRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else if let pageRange = trimmed.range(of: #"\bPAGE\b"#, options: [.caseInsensitive, .regularExpression]) {
                    charSection = String(trimmed[..<pageRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else {
                    charSection = trimmed
                }
                for piece in charSection.components(separatedBy: CharacterSet(charactersIn: ",&/")) {
                    let name = clean(piece)
                    if name.count >= 2 && !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // 1. Character index list in sides packet: "THE CHARACTERS IN THIS DOCUMENT\nNOOR — Page 2\n..."
        let pageListPattern = #"(?m)^([A-Z][A-Za-z0-9'\-]{1,20})\s*[-–—]\s*(?:Page|Pg\.?)\s*\d+"#
        if let pageRegex = try? NSRegularExpression(pattern: pageListPattern) {
            let matches = pageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let name = clean(String(text[r]))
                    if !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // Monologue / character sides cues: e.g. "Roxie:\n", "Velma:\n", "Mama Morton:\n"
        let cueLinesPattern = #"(?m)^([A-Z][A-Za-z\s'\-]{1,24}):\s*$"#
        if let r = try? NSRegularExpression(pattern: cueLinesPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            let nonCueTitles: Set<String> = [
                "audition sides", "for female identifying", "for male identifying", "for any gender",
                "setting", "settings", "director note", "note", "slate", "instructions",
                "stage reading event", "reading event", "event", "dates", "date", "shoot dates", "shoot date",
                "production dates", "rehearsal dates", "submission specs", "specs", "location", "deadline"
            ]
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    let candidate = clean(String(text[range]))
                    let lower = candidate.lowercased()
                    if !nonCueTitles.contains(lower) && !invalidRoleNames.contains(lower) && !lower.contains("event") && !lower.contains("dates") && !lower.contains("specs") {
                        addRole(candidate.capitalized)
                    }
                }
            }
        }

        // 2. Character headers on sides pages: "NOOR · She/her · Early 60s"
        let headerPattern = #"(?m)^([A-Z]{2,20})\s*[·•|\-—]\s*(?:(?:He|She|They)/|[0-9]{1,2}s?\b|Early|Mid|Late)"#
        if let r = try? NSRegularExpression(pattern: headerPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    addRole(String(text[range]).capitalized)
                }
            }
        }

        // 2b. Theatre/stage character breakdown format (Title Case names):
        //     "Maggie - F, 40s. a prostitute; ..."
        //     "Francis - F, 40s. a rancher; ..."
        //     Matches: Name - [M|F|NB|Male|Female|Non-binary], [age] [description]
        //     Also matches "Character Breakdowns" section lists like "Maggie\nF, 40s. ..."
        let theatreBreakdownPattern = #"(?m)^([A-Z][a-z]{1,22}(?:\s+[A-Z][a-z]{1,22})?)\s*[-–—]\s*(?:[FfMmNn][A-Za-z]*(?:on-binary)?)[,.]?\s*(?:\d{1,2}s?\b|Early|Mid|Late|teens?|\d{1,2})"#
        if let r = try? NSRegularExpression(pattern: theatreBreakdownPattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    let name = clean(String(text[range]))
                    if name.count >= 2 && !invalidRoleNames.contains(name.lowercased()) {
                        addRole(name.capitalized)
                    }
                }
            }
        }

        // 2c. "Character Breakdowns" section: standalone role name lines followed by demographics on the next line
        //     e.g. "Character Breakdowns\nMaggie\nF, 40s. ..."
        let breakdownSectionPattern = #"(?is)(?:character\s+breakdowns?|breakdowns?|characters?)\s*\n(.*?)(?=\n\s*(?:note|production|audition|submission|when|how|deadline|\z))"#
        if let r = try? NSRegularExpression(pattern: breakdownSectionPattern),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text) {
            let block = String(text[range])
            // Within the section pick lines that look like character names (Title Case, 2-20 chars)
            for line in block.components(separatedBy: .newlines) {
                let candidate = clean(line)
                guard candidate.count >= 2, candidate.count <= 25 else { continue }
                // Must be a simple Title Case word or two words
                if candidate.range(of: #"^[A-Z][a-z]{1,20}(?:\s+[A-Z][a-z]{1,20})?$"#, options: .regularExpression) != nil {
                    if !invalidRoleNames.contains(candidate.lowercased()) {
                        addRole(candidate)
                    }
                }
            }
        }

        // 3. Slate instruction character: "the role you are reading for (NOOR)"
        let slatePattern = #"(?i)reading\s+for\s*\(([A-Za-z]{2,20})\)"#
        if let r = try? NSRegularExpression(pattern: slatePattern) {
            let matches = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let range = Range(m.range(at: 1), in: text) {
                    addRole(String(text[range]).capitalized)
                }
            }
        }

        // Casting webpages often list role names as standalone lines under a
        // "The Characters" heading, without screenplay-style age or pronoun metadata.
        let characterSectionPattern = #"(?is)\bthe\s+characters\b\s*(.*?)(?=\bcasting\s+sides\b|\bvideo\s+submission\b|\z)"#
        if let r = try? NSRegularExpression(pattern: characterSectionPattern),
           let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(m.range(at: 1), in: text) {
            for line in text[range].components(separatedBy: .newlines) {
                let candidate = clean(line)
                if candidate.range(of: #"^[A-Z][A-Za-z'\-]{1,20}$"#, options: .regularExpression) != nil {
                    addRole(candidate.capitalized)
                }
            }
        }

        // 4. Explicit labeled roles: "Role: Maya", "Character: Arjun".
        // Scan every labeled line (not just the first value) and strip parenthetical
        // casting metadata such as "(Lead, 30s)" from the display name.
        let explicitRolePattern = #"(?im)^\s*(?:role|character|part|playing)\s*:\s*([^\n]+)"#
        if let regex = try? NSRegularExpression(pattern: explicitRolePattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                var roleVal = clean(String(text[valueRange]))
                if let paren = roleVal.firstIndex(of: "(") {
                    roleVal = String(roleVal[..<paren]).trimmingCharacters(in: .whitespaces)
                }
                if let delim = roleVal.range(of: #"\s*(?:[,;–—]|\s*-\s*|\s+(?:who|aged|is|described\s+as)\b).*"#, options: .regularExpression) {
                    roleVal = String(roleVal[..<delim.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                addRole(roleVal.capitalized)
            }
        }

        // Fallback for inline or non-colon labels: "Role Maya", "Character — Arjun".
        if let v = labeled(["role", "character", "part", "playing"], in: text) {
            var roleVal = clean(v)
            if let delim = roleVal.range(of: #"\s*(?:[,;–—]|\s*-\s*|\s+(?:who|aged|is|described\s+as)\b).*"#, options: .regularExpression) {
                let prefix = String(roleVal[..<delim.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty { roleVal = prefix }
            }
            addRole(roleVal.capitalized)
        }

        // 5. Specific character phrasing: "reading for Maya", "role of Kat"
        let name = #"([A-Za-z][A-Za-z.'\-]*(?:\s+[A-Za-z][A-Za-z.'\-]*){0,2}?)"#
        let stop = #"(?=\s+(?:in|on|by|for|from|at|to)\b|\s*[,.;:\n(]|\s*$)"#
        let lead = #"\b(?:role\s+of|part\s+of|character\s+of|playing|audition(?:ing)?\s+for|reading\s+for|self-?tape\s+for|submitting\s+for)\s+(?:the\s+)?(?:role\s+of\s+)?"#
        if let v = firstMatch(lead + name + stop, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
            let cleaned = clean(v)
            let lower = cleaned.lowercased()
            // Skip generic/vague phrases like "your choice", "a character of your choice"
            let isVague = lower.contains("your choice") || lower.contains("any character") || lower.contains("the character")
            if !cleaned.isEmpty, !lower.hasPrefix("age"), !lower.hasPrefix("a "), !isVague {
                addRole(cleaned.capitalized)
            }
        }
        if let v = firstMatch(#"\bfor\s+(?:the\s+role\s+of\s+)?([A-Z][A-Z\-]{1,22})\b"#, in: text) {
            let lowerV = v.lowercased()
            if !invalidRoleNames.contains(lowerV) && lowerV != "female" && lowerV != "male" && lowerV != "any" {
                addRole(v.capitalized)
            }
        }

        // 6. Standard industry role tiers (Lead, Supporting, Series Regular)
        let tierPattern = #"\b(female\s+lead|male\s+lead|lead\s+female|lead\s+male|lead\s+actress|lead\s+actor|supporting\s+actor|supporting\s+actress|supporting\s+lead|series\s+regular)\b"#
        if let regex = try? NSRegularExpression(pattern: tierPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range, in: text) {
                    var tier = clean(String(text[r])).capitalized
                    if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                        let cleanedAge = clean(age)
                        if !tier.contains(cleanedAge) { tier += " (\(cleanedAge))" }
                    }
                    addRole(tier)
                }
            }
        }

        // 7. Demographic breakdowns in casting notices:
        // "Male Age: 20-40 years", "Female Age: 22-60 years", "Male: 20-40", "Female: 20-40", "Boy Age: 8-12", "Girl Age: 8-12"
        let demoPattern = #"(?i)\b(male|female|boy|girl|man|woman)\s*(?:actor|actress|age)?\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs|year old))?)"#
        if let regex = try? NSRegularExpression(pattern: demoPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                let gender = String(text[r1]).capitalized
                let age = clean(String(text[r2]))
                let roleTitle = "\(gender) Actor (\(age))"
                addRole(roleTitle)
            }
        }

        // 7b. Tabular / Columnar demographic breakdowns (e.g. Casting Bay flyer style):
        // AGE \n 18 - 23 years \n AGE \n 45 - 55 years \n GENDER \n Female \n GENDER \n Male
        var detectedAges: [String] = []
        if let ageRegex = try? NSRegularExpression(pattern: #"(?i)(?:^|\b|\n)(?:age|age\s*group)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs|year old))?)"#) {
            let matches = ageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let a = clean(String(text[r]))
                    if !detectedAges.contains(a) { detectedAges.append(a) }
                }
            }
        }
        var detectedGenders: [String] = []
        if let genRegex = try? NSRegularExpression(pattern: #"(?i)(?:^|\b|\n)(?:gender|sex)\s*[:\-]?\s*(male|female|boy|girl|man|woman)\b"#) {
            let matches = genRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let g = clean(String(text[r])).capitalized
                    if !detectedGenders.contains(g) { detectedGenders.append(g) }
                }
            }
        }
        if !detectedAges.isEmpty && !detectedGenders.isEmpty {
            let count = min(detectedAges.count, detectedGenders.count)
            for i in 0..<count {
                let rTitle = "\(detectedGenders[i]) (\(detectedAges[i]))"
                addRole(rTitle)
            }
        }

        // 8. Seeking/looking for — strict validation so acting directions/adjectives never become roles
        let nonRoleWords: Set<String> = [
            "passionate", "grounded", "authentic", "talented", "experienced", "fresh", "creative",
            "charismatic", "diverse", "local", "real", "natural", "subtle", "dynamic", "versatile",
            "submissions", "actors", "actresses", "performers", "artists", "talent", "people",
            "individuals", "faces", "new faces", "all ethnicities", "any ethnicity", "upcoming project"
        ]
        let seekLead = #"\b(?:looking\s+for|seeking|cast(?:ing)?\s+for|in\s+search\s+of)\s+(?:a\s+|an\s+)?([A-Za-z0-9\s\-/]{2,30}?)(?=\s+(?:for|in|as|who|aged?)\b|\s*[,.;:\n])"#
        if let v = firstMatch(seekLead, in: text, options: .caseInsensitive) {
            let cleaned = clean(v)
            let lower = cleaned.lowercased()
            let firstWord = lower.components(separatedBy: .whitespaces).first ?? ""
            let isNonRole = nonRoleWords.contains(lower) || nonRoleWords.contains(firstWord)
            let isDemographicOnly = lower.hasPrefix("age") || lower.contains("year old") || lower.contains("yrs old") || lower.range(of: #"^\d{1,2}\s*[-–]"#, options: .regularExpression) != nil
            if !cleaned.isEmpty && !isNonRole && !isDemographicOnly && !roles.contains(where: { $0.lowercased().contains(cleaned.lowercased()) }) {
                var res = cleaned.capitalized
                if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                    let cleanedAge = clean(age)
                    if !res.contains(cleanedAge) { res += " (\(cleanedAge))" }
                }
                addRole(res)
            }
        }

        // Filter out compound "Male and Female" when individual male and female roles are present
        if roles.contains(where: { $0.lowercased().hasPrefix("male") }) && roles.contains(where: { $0.lowercased().hasPrefix("female") }) {
            roles.removeAll(where: { $0.lowercased().contains("male and female") || $0.lowercased().contains("male & female") })
        }

        // Filter out any blacklisted notice words or location names
        return roles.filter { role in
            let base = role.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? role
            if base.lowercased() == "male" || base.lowercased() == "female" { return true }
            return !ScriptParser.isBlacklistedNoticeWord(base)
        }
    }

    static func detectRole(in text: String) -> String? {
        detectCandidateRoles(in: text).first
    }

    static func detectLocation(in text: String) -> String? {
        if let v = labeled(["location", "city", "venue", "place", "based in", "shoot location"], in: text) {
            return clean(v).capitalized
        }
        for city in ["Bengaluru", "Bangalore", "Mumbai", "Delhi", "New Delhi", "Hyderabad", "Chennai", "Kolkata", "Pune", "Goa", "Jaipur", "Kochi", "New York", "Los Angeles", "London", "Toronto", "Vancouver"] {
            let pattern = #"(?i)\b(?:location|in|at)\s*[:\-]?\s*"# + city + #"\b"#
            if firstMatch(pattern, in: text) != nil {
                return city
            }
        }
        return nil
    }

    static func isGenericHeadline(_ s: String) -> Bool {
        let lower = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*\"' \t\r\n"))
        let words = [
            "casting", "audition", "sides", "notice", "call", "how to use", "page", "scene", "script",
            "breakdown", "character", "characters", "urgent", "open call", "casting call", "casting notice",
            "urgent casting", "commercial", "feature film", "theatre", "confidential", "for audition use only",
            "do not distribute", "not for distribution", "all rights reserved", "property of", "untitled"
        ]
        return words.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ":") })
    }

    static func isSluglineOrScene(_ s: String) -> Bool {
        let upper = s.uppercased().trimmingCharacters(in: .whitespaces)
        let prefixes = ["INT.", "EXT.", "INT/EXT", "EXT/INT", "I/E", "INT ", "EXT ", "SCENE ", "SC.", "ACT "]
        return prefixes.contains(where: { upper.hasPrefix($0) })
    }

    /// Labeled "Project:" / "Title:", explicit project folder, prominent header, then "in THE LAST SUMMER (feature)".
    /// Never returns scene headings, character names, casting office names, dates, or watermarks.
    static func detectProject(in text: String) -> String? {
        func cleanTitle(_ s: String) -> String? {
            var title = clean(s)
            guard !title.isEmpty, title.count >= 2, title.count <= 50 else { return nil }
            if isNoiseLine(title) || isSluglineOrScene(title) { return nil }
            // Strip leading prefixes like "Casting Call:", "Casting Notice:", "Project:", "Audition Call:"
            let prefixes = [
                #"(?i)^casting\s+call\s*[:\-]\s*"#,
                #"(?i)^casting\s+notice\s*[:\-]\s*"#,
                #"(?i)^now\s+casting\s*[:\-]\s*"#,
                #"(?i)^urgent\s+casting\s*[:\-]\s*"#,
                #"(?i)^project\s*[:\-]\s*"#,
                #"(?i)^audition\s*(?:call|notice)?\s*[:\-]\s*"#
            ]
            for p in prefixes {
                if let r = title.range(of: p, options: .regularExpression) {
                    title = String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if isGenericHeadline(title) { return nil }
            let lower = title.lowercased()
            if lower.hasPrefix("role:") || lower.hasPrefix("character:") || lower.hasPrefix("part:") || lower.hasPrefix("sides:") || lower.hasPrefix("download:") || lower.hasPrefix("due:") { return nil }
            if lower.hasSuffix("casting") || lower.contains("casting director") || lower.contains("page ") { return nil }
            // Clean trailing role information e.g. "The Last Summer - Role of Maya" -> "The Last Summer"
            if let idx = title.range(of: #"\s*[-–—]\s*(?:Role|Part|Character)\b.*"#, options: .regularExpression) {
                title = String(title[..<idx.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return title.isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }

        // Resolve the play title before a generic “in …” match can mistake its synopsis
        // (“in a small western town…”) for the project name.
        if let title = firstMatch(#"(?i)\bworld\s+premiere\s+production\s+of\s+([^,\n.]{2,50})"#, in: text),
           let valid = cleanTitle(title) {
            return valid
        }

        // Premier/world-premiere phrasing: e.g. "world premiere production of Eve's Ale"
        // Also handles: "premiere of X", "production of X", "staging of X"
        let premierePhrases = [
            #"(?i)\b(?:world\s+premiere|world\s+premiere\s+production|premiere\s+production|premiere)\s+of\s+([A-Za-z0-9'&,\s\-]{2,45}?)(?=\s*[,.\n(]|\s+by\b|\s*$)"#,
            #"(?i)\b(?:production\s+of|staging\s+of|adaptation\s+of|revival\s+of)\s+([A-Za-z0-9'&,\s\-]{2,45}?)(?=\s*[,.\n(]|\s+by\b|\s+a\b|\s*$)"#,
        ]
        for pattern in premierePhrases {
            if let v = firstMatch(pattern, in: text), let valid = cleanTitle(v.trimmingCharacters(in: .whitespaces)) {
                return valid
            }
        }

        // Show / musical / production phrasing: e.g. "GREASE is such a fun production"
        let showPattern = #"(?i)\b([A-Z][A-Za-z0-9 '\-]{2,25})\s+is\s+(?:a|an|such\s+a)\s+(?:fun\s+)?(?:production|musical|play|film|movie|show|series|theatrical)\b"#
        if let showMatch = firstMatch(showPattern, in: text), let valid = cleanTitle(showMatch) {
            return valid
        }

        // Catchy banner phrasing: e.g. "ROXIE ROCKS CHICAGO."
        let bannerPattern = #"(?i)\b[A-Za-z]+\s+ROCKS\s+([A-Za-z0-9'\-]{2,30})\b"#
        if let bannerMatch = firstMatch(bannerPattern, in: text), let valid = cleanTitle(bannerMatch) {
            return valid
        }

        // 1. Explicit high-confidence call line: "Casting Call: Ad Film", "Now Casting: <Title>"
        if let callMatch = firstMatch(#"(?im)^(?:casting\s+call|now\s+casting|urgent\s+casting)\s*[:\-]\s*([A-Za-z0-9\s'&,\-]{2,40})$"#, in: text),
           let valid = cleanTitle(callMatch) {
            return valid
        }

        // 2. Explicitly labeled: "Project: ...", "Title: ...", "Project folder \"...\""
        if let v = firstMatch(#"(?:project\s+folder|project(?:\s+name|\s+title)?|title|film\s+title|series\s+title|show\s+title)\s*[:\-]?\s*["“]([^"”\n]+)["”]"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }
        if let v = labeled(["project name", "project title", "film title", "series title", "show title", "project folder", "title", "project"], in: text),
           let valid = cleanTitle(v) {
            return valid
        }

        // 3. Quoted title when the notice explicitly calls it a subject, folder, or title
        if let v = firstMatch(#"\bmention\s+["“]([^"”\n]{2,45})["”]\s+in\s+(?:the\s+)?(?:email\s+)?subject\b"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }
        if let v = firstMatch(#"(?:subject|folder|titled|called|project)\s*[:\-]?\s*["“]([^"”\n]{2,45})["”]"#, in: text, options: .caseInsensitive),
           let valid = cleanTitle(v) {
            return valid
        }

        // 4. Prominent project title immediately preceding "CASTING SIDES", "AUDITION SIDES", "CASTING NOTICE", "CASTING CALL"
        let lines = text.components(separatedBy: .newlines).map { clean($0) }.filter { !$0.isEmpty }
        let sideKeywords = ["CASTING SIDES", "AUDITION SIDES", "CASTING NOTICE", "CASTING CALL", "AUDITION NOTICE", "SIDES"]

        // Web casting pages commonly put the title between the call label and the venue,
        // rather than on a standalone line before "CASTING SIDES".
        if let first = lines.first,
           let match = first.range(of: #"(?i)^casting\s+call\s*[-–—:]\s*([^|]+?)(?:\s*\|.*)?$"#, options: .regularExpression) {
            let candidate = String(first[match]).replacingOccurrences(
                of: #"(?i)^casting\s+call\s*[-–—:]\s*|\s*\|.*$"#,
                with: "",
                options: .regularExpression
            )
            if let valid = cleanTitle(candidate) { return valid }
        }
        if lines.count > 2, lines[1].lowercased().contains("for the new play"),
           let valid = cleanTitle(lines[2]) {
            return valid
        }

        for i in 0..<min(lines.count - 1, 8) {
            let line = lines[i]
            let nextLine = lines[i + 1].uppercased()
            if sideKeywords.contains(where: { nextLine == $0 || nextLine.hasPrefix($0 + " ") || nextLine.hasPrefix($0 + "-") }) {
                if !line.lowercased().hasPrefix("role:") && !line.lowercased().hasPrefix("character:") {
                    if let valid = cleanTitle(line) {
                        return valid
                    }
                }
            }
        }

        // 5. First line if standalone title followed by author or casting metadata
        if let firstLine = lines.first, !isNoiseLine(firstLine), let valid = cleanTitle(firstLine) {
            let lower = text.lowercased()
            if lower.contains("casting") || lower.contains("sides") || lower.contains("audition") {
                if lines.count > 1 {
                    let secondLine = lines[1].uppercased()
                    if secondLine.contains("CASTING") || secondLine.contains("SIDES") || secondLine.contains("BY ") || secondLine.contains("&") || secondLine.contains("DIRECTOR") {
                        return valid
                    }
                }
            }
        }

        // 6. Specific project phrasing: "Self-tape for MAYA in THE LAST SUMMER (feature)"
        let inPattern = #"(?i)\b(?:audition(?:ing)?\s+for|self-?tape\s+for|reading\s+for)\s+[A-Za-z0-9'\-]+\s+in\s+([A-Z][A-Za-z0-9'&, \-]{2,40}?)(?=\s*[\(.,]|\s+by\b|\s*$)"#
        if let v = firstMatch(inPattern, in: text), let valid = cleanTitle(v) {
            return valid
        }
        // This fallback intentionally requires an all-caps title. A case-insensitive
        // `[A-Z]` also matches lowercase text and used to turn synopsis phrases such as
        // “in a small western town...” into the project name.
        if let v = firstMatch(#"\bin\s+([A-Z][A-Z0-9'&, \-]{2,40}?)(?=\s*[\(.,]|\s+by\b|\s*$)"#, in: text),
           let valid = cleanTitle(v), detectLocation(in: valid) == nil {
            return valid
        }

        // 7. Standalone project mention e.g. "AD FILM" at bottom or header
        if let adFilm = firstMatch(#"(?im)^[\s>*•\-\[\]]*AD\s+FILM[\s>*•\-\[\]]*$"#, in: text) {
            let _ = adFilm
            return "Ad Film"
        }

        return nil
    }

    static func detectCastingOffice(in text: String) -> String? {
        let genericCastingWords: Set<String> = [
            "casting", "casting call", "casting notice", "urgent casting", "open casting", "open call",
            "commercial casting", "theatrical casting", "film casting", "feature film casting", "series casting",
            "tv casting", "television casting", "child casting", "voice casting", "worldwide casting", "online casting",
            "self-tape casting", "sides casting", "audition casting", "actors casting", "acting", "audition",
            "casting call bengaluru", "casting call mumbai", "casting call delhi", "bengaluru casting",
            "mumbai casting", "delhi casting", "london casting", "nyc casting", "la casting", "los angeles casting",
            "history casting", "now casting", "casting now",
            // Section-header phrases that contain "casting" but are not company names:
            "note on casting", "a note on casting", "casting note", "note casting"
        ]

        // Acronym or compound casting companies like Mukesh Chhabra Casting Company (MCCC)
        if firstMatch(#"(?i)\b(Mukesh\s+Chhabra\s+Casting\s+Company(?:\s*\(MCCC\))?|MCCC)\b"#, in: text) != nil {
            return "Mukesh Chhabra Casting Company (MCCC)"
        }

        if let office = labeled(["casting director", "casting office", "casting company", "casting agency", "casting by"], in: text) {
            let cleaned = clean(office)
            let lower = cleaned.lowercased()
            let isEditorialNote = lower.hasPrefix("note on casting") || lower.hasPrefix("a note on casting")
            if !cleaned.isEmpty && !isEditorialNote && !genericCastingWords.contains(lower) && !isNoiseLine(cleaned) {
                return cleaned.capitalized
            }
        }

        // Check for "Casting <Name>" (e.g. "Casting Bay", "Casting Collective", "Casting Works")
        if let v = firstMatch(#"(?im)^[\s>*•\-]*Casting[ \t]+([A-Z][A-Za-z0-9\-]+)(?:'|\b)"#, in: text) {
            let full = "Casting \(clean(v))"
            let lower = full.lowercased().replacingOccurrences(of: "\n", with: " ")
            if !genericCastingWords.contains(lower) && !lower.contains("call") && !lower.contains("notice") && !lower.contains("director") && !lower.contains("mumbai") {
                return full.capitalized
            }
        }
        if let v = firstMatch(#"\b(Casting[ \t]+[A-Z][A-Za-z0-9\-]+)\b"#, in: text) {
            let lower = v.lowercased().replacingOccurrences(of: "\n", with: " ")
            if !genericCastingWords.contains(lower) && !lower.contains("call") && !lower.contains("notice") && !lower.contains("director") && !lower.contains("sides") && !lower.contains("mumbai") {
                return clean(v).capitalized
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            let lower = line.lowercased()
            if lower.hasSuffix("casting") &&
                !genericCastingWords.contains(lower) &&
                !lower.contains("casting call") &&
                !lower.contains("casting sides") &&
                !lower.contains("download casting") &&
                !lower.contains("theater lab") &&
                !lower.contains("the lab") &&
                !lower.contains("pilgrimage casting") &&
                !lower.hasPrefix("note on") &&
                !lower.hasPrefix("a note on") &&
                !lower.hasPrefix("note:") &&
                !isNoiseLine(line) &&
                line.count <= 45 {
                return line.capitalized
            }
        }
        if let v = firstMatch(#"\b((?:[A-Z][A-Za-z0-9\-]+[ \t]+){1,2}Casting)\b"#, in: text, options: .caseInsensitive) {
            let cleaned = clean(v).replacingOccurrences(of: ".", with: "-")
            let lower = cleaned.lowercased()
            if !lower.hasPrefix("note on casting") && !lower.hasPrefix("a note on casting") &&
                !genericCastingWords.contains(lower) &&
                !lower.contains("casting call") &&
                !lower.contains("casting sides") &&
                !lower.contains("download casting") &&
                !lower.contains("pilgrimage casting") &&
                !isNoiseLine(cleaned) {
                return cleaned.capitalized
            }
        }
        if let v = firstMatch(#"@([A-Za-z0-9\-]+casting)\.[a-z]+"#, in: text, options: .caseInsensitive) {
            return clean(v).capitalized
        }
        // Match casting portal domain e.g. "apply at castingbay.app" -> "Casting Bay"
        if let domain = firstMatch(#"(?i)\b(?:apply\s+at\s+|visit\s+)?([a-z0-9\-]+casting|casting[a-z0-9\-]+)\.(?:app|com|in|co|org|net|io)\b"#, in: text) {
            let lowerDomain = domain.lowercased()
            if lowerDomain.hasPrefix("casting") {
                let name = String(lowerDomain.dropFirst("casting".count))
                if !name.isEmpty {
                    return "Casting \(name.capitalized)"
                }
            }
        }
        return nil
    }

    /// "Sides attached (2 scenes)" — any "<N> scene(s)" mention.
    static func detectSceneCount(in text: String) -> Int? {
        guard let v = firstMatch(#"(\d+)\s+scenes?"#, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }

    /// "under 3 minutes", "no more than 2 min", "max 5 minutes".
    static func detectLengthLimit(in text: String) -> Int? {
        let pattern = #"(?:under|less than|no more than|max(?:imum)?(?: of)?|up to|within)\s+(\d{1,2})\s*(?:min|minute)"#
        guard let v = firstMatch(pattern, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }

    /// Context-aware link classifier that inspects the text and labels immediately before each URL
    /// to determine whether each link is intended for tape upload/submission or for script sides/audition material.
    static func detectClassifiedLinks(in text: String) -> (sidesLink: String?, submissionLink: String?) {
        let urlPattern = #"(?i)\b((?:https?:\/\/|www\.)[^\s<>"'\)]+|[a-zA-Z0-9.\-]+\.(?:com|org|net|io|in|co|us|uk|ca|gov|edu|me|ly|gl)\/[^\s<>"'\)]*)"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return (nil, nil) }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var sidesLink: String?
        var submissionLink: String?

        let uploadKeywords = [
            "upload", "upload tape", "upload your tape", "upload audition", "upload video", "upload here",
            "submit", "submit tape", "submit audition", "submit your tape", "submit here", "submission",
            "submission link", "submission form", "submission url", "send tape", "send your tape",
            "send audition", "send submissions", "send video", "apply", "apply here", "application form",
            "audition form", "tape link", "form to submit", "google form", "tape upload", "turn in",
            "drop tape", "share your tape", "link to submit", "link for tape", "link for submission"
        ]

        let sidesKeywords = [
            "sides", "sides link", "sides url", "sides folder", "audition sides", "dialogue sides", "casting sides",
            "script", "script link", "script url", "script folder", "full script", "screenplay", "lines",
            "download sides", "download script", "download scenes", "download material", "download lines",
            "scenes", "scene material", "audition material", "material link", "reading material", "packet",
            "find sides", "access sides", "sides attached", "sides available", "drive link for sides",
            "sides can be found", "script attached", "scene sides", "materials"
        ]

        for m in matches {
            guard let r = Range(m.range, in: text) else { continue }
            let link = clean(String(text[r]))
            guard !link.contains("@") else { continue }

            // 1. Inspect text immediately preceding this link (same line + preceding line, up to 160 characters)
            let lineRange = text.lineRange(for: r)

            var priorLine = ""
            if lineRange.lowerBound > text.startIndex {
                let prevIdx = text.index(before: lineRange.lowerBound)
                let prevLineRange = text.lineRange(for: prevIdx..<prevIdx)
                priorLine = String(text[prevLineRange]).lowercased()
            }

            let startOffset = max(text.startIndex, text.index(r.lowerBound, offsetBy: -160, limitedBy: text.startIndex) ?? text.startIndex)
            let contextBefore = String(text[startOffset..<r.lowerBound]).lowercased()

            // 2. Check for upload vs sides keywords in the preceding context
            var hasUpload = false
            var lastUploadIdx = -1
            for kw in uploadKeywords {
                if let range = contextBefore.range(of: kw, options: .backwards) {
                    hasUpload = true
                    let dist = contextBefore.distance(from: contextBefore.startIndex, to: range.lowerBound)
                    lastUploadIdx = max(lastUploadIdx, dist)
                } else if priorLine.contains(kw) {
                    hasUpload = true
                    lastUploadIdx = max(lastUploadIdx, 0)
                }
            }

            var hasSides = false
            var lastSidesIdx = -1
            for kw in sidesKeywords {
                if let range = contextBefore.range(of: kw, options: .backwards) {
                    hasSides = true
                    let dist = contextBefore.distance(from: contextBefore.startIndex, to: range.lowerBound)
                    lastSidesIdx = max(lastSidesIdx, dist)
                } else if priorLine.contains(kw) {
                    hasSides = true
                    lastSidesIdx = max(lastSidesIdx, 0)
                }
            }

            // 3. Classify based on text preceding the link
            if hasUpload && !hasSides {
                if submissionLink == nil { submissionLink = link }
            } else if hasSides && !hasUpload {
                if sidesLink == nil { sidesLink = link }
            } else if hasUpload && hasSides {
                // If both keywords appear, the keyword closest to the link wins
                if lastUploadIdx >= lastSidesIdx {
                    if submissionLink == nil { submissionLink = link }
                } else {
                    if sidesLink == nil { sidesLink = link }
                }
            } else {
                // 4. Neither keyword in preceding text: fall back to domain/service heuristics
                let lowerLink = link.lowercased()
                if lowerLink.contains("forms.gle") || lowerLink.contains("docs.google.com/forms") ||
                   lowerLink.contains("typeform.com") || lowerLink.contains("airtable.com") {
                    if submissionLink == nil { submissionLink = link }
                } else if lowerLink.contains("drive.google.com") || lowerLink.contains("docs.google.com/document") ||
                          lowerLink.contains("dropbox.com") || lowerLink.contains("1drv.ms") ||
                          lowerLink.contains("onedrive.live.com") || lowerLink.contains("box.com") {
                    if sidesLink == nil { sidesLink = link }
                } else {
                    // Check URL path clues
                    if lowerLink.contains("upload") || lowerLink.contains("submit") || lowerLink.contains("form") || lowerLink.contains("apply") {
                        if submissionLink == nil { submissionLink = link }
                    } else if lowerLink.contains("side") || lowerLink.contains("script") || lowerLink.contains("material") || lowerLink.contains("scene") {
                        if sidesLink == nil { sidesLink = link }
                    } else if submissionLink == nil {
                        submissionLink = link
                    }
                }
            }
        }

        return (sidesLink, submissionLink)
    }

    static func detectSidesLink(in text: String) -> String? {
        detectClassifiedLinks(in: text).sidesLink
    }
}
