import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import UserNotifications

/// 06 Add an audition capture sheet
struct AddAuditionFlow: View {
    enum ReaderAudioPlan: Hashable { case recordNow, later }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var unreadableNoticeError = false

    var body: some View {
        capture
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { pages in
                    showScanner = false
                    guard !pages.isEmpty else { return }
                    Task {
                        let text = await NoticeOCR.recognizeText(in: pages)
                        await MainActor.run {
                            if !NoticeOCR.looksReadable(text) {
                                unreadableNoticeError = true
                            } else {
                                let draft = NoticeParser.parse(text)
                                store.startAuditionDraft(draft)
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
                switch result {
                case .success(let url):
                    let accessed = url.startAccessingSecurityScopedResource()
                    let text = NoticeOCR.extractText(fromFileAt: url)
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    if let text, NoticeOCR.looksReadable(text) {
                        let draft = NoticeParser.parse(text)
                        store.startAuditionDraft(draft)
                    } else {
                        unreadableNoticeError = true
                    }
                case .failure:
                    unreadableNoticeError = true
                }
            }
            .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
            }
            .alert("We couldn't read this notice", isPresented: $unreadableNoticeError) {
                Button("Type details") { store.startAuditionDraft(NoticeParser.Draft.blank) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("No readable text was found — it may be blurry or very small print. You can type the details instead.")
            }
            .task { await readSharedNotice() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        await MainActor.run { unreadableNoticeError = true }
                        return
                    }
                    let text = await NoticeOCR.recognizeText(in: [image])
                    await MainActor.run {
                        if !NoticeOCR.looksReadable(text) {
                            unreadableNoticeError = true
                        } else {
                            let draft = NoticeParser.parse(text)
                            store.startAuditionDraft(draft)
                        }
                    }
                }
            }
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true } else { scannerUnavailable = true }
    }

    private func readSharedNotice() async {
        guard let item = store.incomingShare else { return }
        store.incomingShare = nil
        var parts: [String] = []
        if let text = item.text, !text.isEmpty { parts.append(text) }
        parts += item.pdfs.compactMap(NoticeOCR.extractText(fromFileAt:))
        let images = item.images.compactMap { UIImage(contentsOfFile: $0.path) }
        if !images.isEmpty { parts.append(await NoticeOCR.recognizeText(in: images)) }
        ShareInbox.remove(item)
        let text = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            if !NoticeOCR.looksReadable(text) {
                unreadableNoticeError = true
            } else {
                let draft = NoticeParser.parse(text)
                store.startAuditionDraft(draft)
            }
        }
    }

    private var capture: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Add an audition").font(.otTitle)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(OT.accent)
                            .frame(width: 36, height: 36).background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading) {
                            Text("Copied notice or sides?").font(.otHeadline)
                            Text("Paste breakdown, casting email, or script dialogue").font(.otFootnote).foregroundStyle(OT.labelSecondary)
                        }
                    }
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        let draft = NoticeParser.parse(text)
                        store.startAuditionDraft(draft)
                    }
                    .buttonBorderShape(.capsule)
                    .tint(OT.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OT.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                SectionLabel(text: "Or bring in notice or sides")
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { way("photo", "Photo") }
                    Button { openScanner() } label: { way("doc.viewfinder", "Scan") }
                    Button { showFileImporter = true } label: { way("folder", "File") }
                    Button { store.startAuditionDraft(NoticeParser.Draft.blank) } label: { way("keyboard", "Type it") }
                }
                .buttonStyle(.plain)

                Label("Faster: in Mail or WhatsApp, Share → OneTake", systemImage: "square.and.arrow.up")
                    .font(.otFootnote).foregroundStyle(OT.accent)
            }
            .padding(OT.gutter)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func way(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(OT.labelPrimary)
                .frame(width: 52, height: 52).background(OT.fillField, in: Circle())
            Text(title).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Notice parsing (on-device, rule-based — runs on whatever real text OCR/the file importer found)

enum NoticeParser {
    struct Draft: Hashable {
        var project = ""
        var role = ""
        var castingOffice = ""
        var projectType = "Feature film"
        var due: Date?
        var scenes = 0
        var asks: [String] = []
        var aiGuidance = ""
        var destination: Destination = .actorsAccess
        /// The real recognised text this draft came from — kept so `makeAudition()` can parse real
        /// sides out of it instead of substituting a canned scene.
        var sourceText = ""

        static let blank = Draft()

        var hasSides: Bool {
            !ScriptParser.parseScenes(from: sourceText, myRole: role).isEmpty
        }

        var missingRequiredDetails: [String] {
            var missing: [String] = []
            if project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("project") }
            if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("role") }
            if due == nil { missing.append("due date") }
            if !hasSides { missing.append("script sides") }
            return missing
        }

        func makeAudition() -> Audition {
            let parsedScenes = ScriptParser.parseScenes(from: sourceText, myRole: role)
            var pieces: [Piece] = [
                .init(kind: .headshot, title: "Headshot", detail: "Front", isDone: false),
                .init(kind: .slate, title: "Slate", detail: "Name, height, city", isDone: false)
            ]
            if parsedScenes.isEmpty {
                // No sides could be read from what was captured — be honest about that rather than
                // filling in a stand-in scene. Pieces still exist so the checklist has something to
                // point at; "Add sides" is left for the actor to do once they have the real pages.
                for i in 0..<max(scenes, 1) {
                    pieces.append(.init(kind: .scene, title: "Scene \(i + 1)", detail: "No sides yet — add them", isDone: false))
                }
            } else {
                for scene in parsedScenes {
                    pieces.append(.init(kind: .scene, title: scene.title, detail: "", isDone: false))
                }
            }
            return Audition(project: project.isEmpty ? "Untitled audition" : project, projectType: projectType,
                            role: role.isEmpty ? "Role" : role, roleSize: "Lead", castingOffice: castingOffice.isEmpty ? "Casting office" : castingOffice,
                            due: due ?? .now.addingTimeInterval(3 * 86400),
                            asks: asks, pieces: pieces, scenes: parsedScenes,
                            scriptText: sourceText.isEmpty ? nil : sourceText,
                            destination: destination, status: .due)
        }
    }

    static func parse(_ rawText: String) -> Draft {
        var d = Draft()
        d.sourceText = rawText
        // OCR joins lines oddly and swaps quotes/dashes; work on a tidied copy for field detection.
        let text = tidy(rawText)
        let lower = text.lowercased()

        d.due = detectDate(in: text)
        if let role = detectRole(in: text) { d.role = role }
        if let project = detectProject(in: text) { d.project = project }
        if let office = detectCastingOffice(in: text) {
            d.castingOffice = office
        }
        if let explicit = detectSceneCount(in: text) {
            d.scenes = max(explicit, 0)
        } else {
            d.scenes = ScriptParser.parseScenes(from: rawText, myRole: d.role).count
        }

        func ask(_ s: String) { if !d.asks.contains(s) { d.asks.append(s) } }
        if lower.contains("slate") { ask("Slate first") }
        if lower.contains("landscape") || lower.contains("horizontal") { ask("Landscape") }
        if lower.contains("full-length") || lower.contains("full length") || lower.contains("full body") || lower.contains("full-body") {
            ask("Full length")
        }
        if lower.contains("intro video") || lower.contains("intro") { ask("Intro video") }
        if lower.contains("picture") || lower.contains("photo") || lower.contains("headshot") { ask("Headshots") }
        if let email = firstMatch(#"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"#, in: text) {
            ask("Email: \(email)")
        }
        if let minutes = detectLengthLimit(in: text) { ask("Under \(minutes) min") }
        if lower.contains("feature") { d.projectType = "Feature film" }
        else if lower.contains("series") || lower.contains("episod") { d.projectType = "Series" }
        else if lower.contains("theatre") || lower.contains("theater") { d.projectType = "Theatre" }
        for dest in Destination.allCases where lower.contains(dest.rawValue.lowercased()) {
            d.destination = dest
            ask(dest.rawValue)
        }
        return d
    }

    /// Normalises OCR output: unified quotes/dashes/newlines, no zero-width characters.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "\u{200B}", with: "")
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.range(at: group).location != NSNotFound,
          let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'*_.,;:-#“"))
    }

    /// "Role: Maya", "Project - The Last Summer" — a label at the start of a line, then its value.
    private static func labeled(_ labels: [String], in text: String) -> String? {
        for label in labels {
            let pattern = #"^[\s>*•\-]*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*[:\-]\s*(.+)$"#
            if let value = firstMatch(pattern, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
                let cleaned = clean(value)
                if !cleaned.isEmpty, cleaned.count <= 60 { return cleaned }
            }
        }
        return nil
    }

    /// Prefers a date near "due / deadline / submit / by" over the first date anywhere in the notice.
    private static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let keywords = ["due", "deadline", "submit", "submission", "no later", "before", "by "]
        for match in matches {
            guard let date = match.date, let r = Range(match.range, in: text) else { continue }
            let line = text.lineRange(for: r)
            let context = text[line].lowercased()
            if keywords.contains(where: { context.contains($0) }) { return date }
        }
        return matches.first?.date
    }

    /// Labeled "Role:" first, then common role types, phrases like "for the role of Maya in …", then the old ALL-CAPS cue.
    private static func detectRole(in text: String) -> String? {
        if let v = labeled(["role", "character", "part", "playing"], in: text) { return v.capitalized }

        if let v = firstMatch(#"\b(female\s+lead|male\s+lead|lead\s+female|lead\s+male|lead\s+actress|lead\s+actor|supporting\s+actor|supporting\s+actress|supporting\s+lead|series\s+regular)\b"#, in: text, options: .caseInsensitive) {
            var res = clean(v).capitalized
            if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                res += " (\(clean(age)))"
            }
            return res
        }

        let seekLead = #"\b(?:looking\s+for|seeking|cast(?:ing)?\s+for|in\s+search\s+of)\s+(?:a\s+|an\s+)?([A-Za-z0-9\s\-/]{2,30}?)(?=\s+(?:for|in|as|who|aged?)\b|\s*[,.;:\n])"#
        if let v = firstMatch(seekLead, in: text, options: .caseInsensitive) {
            let cleaned = clean(v)
            if !cleaned.isEmpty {
                var res = cleaned.capitalized
                if let age = firstMatch(#"(?:age(?:\s+group)?|aged?)\s*[:\-]?\s*(\d{1,2}\s*[-–to]\s*\d{1,2}(?:\s*(?:years|yrs))?)"#, in: text, options: .caseInsensitive) {
                    res += " (\(clean(age)))"
                }
                return res
            }
        }

        let name = #"([A-Za-z][A-Za-z.'\-]*(?:\s+[A-Za-z][A-Za-z.'\-]*){0,2}?)"#
        let stop = #"(?=\s+(?:in|on|by|for|from|at|to)\b|\s*[,.;:\n(]|\s*$)"#
        let lead = #"\b(?:role\s+of|part\s+of|character\s+of|playing|audition(?:ing)?\s+for|reading\s+for|self-?tape\s+for|submitting\s+for)\s+(?:the\s+)?(?:role\s+of\s+)?"#
        if let v = firstMatch(lead + name + stop, in: text, options: [.caseInsensitive, .anchorsMatchLines]) {
            let cleaned = clean(v)
            if !cleaned.isEmpty { return cleaned.capitalized }
        }
        if let v = firstMatch(#"\bfor\s+(?:the\s+role\s+of\s+)?([A-Z][A-Z\-]{1,22})\b"#, in: text) { return v.capitalized }
        return nil
    }

    /// Labeled "Project:" / "Title:", explicit project folder, then a quoted title, then "in THE LAST SUMMER (feature)".
    private static func detectProject(in text: String) -> String? {
        if let v = firstMatch(#"(?:project\s+folder|project(?:\s+name)?|title)\s*[:\-]?\s*["“]([^"”\n]+)["”]"#, in: text, options: .caseInsensitive) {
            return clean(v).capitalized
        }
        if let v = labeled(["project", "title", "production", "film", "series", "show"], in: text) { return v.capitalized }

        let genericHeadlines = ["casting call", "audition", "auditions", "casting notice", "urgent casting", "casting", "notice", "open call"]
        if let regex = try? NSRegularExpression(pattern: #"["“]([^"”\n]{3,60})["”]"#) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let r = Range(m.range(at: 1), in: text) {
                    let candidate = clean(String(text[r]))
                    if !genericHeadlines.contains(candidate.lowercased()) {
                        return candidate.capitalized
                    }
                }
            }
        }

        if let v = firstMatch(#"\bin\s+([A-Z][A-Z0-9'&, \-]{2,40}?)(?:\s*[\(.,]|\s+by\s|$)"#, in: text) {
            let cleaned = clean(v)
            return cleaned.isEmpty ? nil : cleaned.capitalized
        }
        return nil
    }

    private static func detectCastingOffice(in text: String) -> String? {
        if let office = labeled(["casting director", "casting office", "casting company", "casting", "agency"], in: text) {
            return office
        }
        let ignoredLines = ["casting", "casting call", "casting notice", "urgent casting", "open casting", "open call"]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            let lower = line.lowercased()
            if lower.hasSuffix("casting") && !ignoredLines.contains(lower) {
                return line
            }
        }
        if let v = firstMatch(#"\b([A-Za-z0-9\-]+\s*[-.]?\s*Casting)\b"#, in: text, options: .caseInsensitive) {
            let cleaned = clean(v).replacingOccurrences(of: ".", with: "-")
            if !ignoredLines.contains(cleaned.lowercased()) {
                return cleaned.capitalized
            }
        }
        if let v = firstMatch(#"@([A-Za-z0-9\-]+casting)\.[a-z]+"#, in: text, options: .caseInsensitive) {
            return clean(v).capitalized
        }
        return nil
    }

    /// "Sides attached (2 scenes)" — any "<N> scene(s)" mention.
    private static func detectSceneCount(in text: String) -> Int? {
        guard let v = firstMatch(#"(\d+)\s+scenes?"#, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }

    /// "under 3 minutes", "no more than 2 min", "max 5 minutes".
    private static func detectLengthLimit(in text: String) -> Int? {
        let pattern = #"(?:under|less than|no more than|max(?:imum)?(?: of)?|up to|within)\s+(\d{1,2})\s*(?:min|minute)"#
        guard let v = firstMatch(pattern, in: text, options: .caseInsensitive) else { return nil }
        return Int(v)
    }
}

// MARK: - 6.1 Draft sides sheet (Add or replace sides during audition creation)

struct AddDraftSidesSheet: View {
    @Binding var draft: NoticeParser.Draft
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false
    @State private var reading = false

    private var parsed: [ScriptScene] {
        ScriptParser.parseScenes(from: text, myRole: draft.role)
    }

    var body: some View {
        VStack(spacing: 0) {
            InContentNavHeader(
                title: draft.hasSides ? "Replace sides" : "Add sides",
                backLabel: "Cancel",
                onBack: { dismiss() }
            ) {
                Button(draft.hasSides ? "Replace" : "Add") {
                    draft.sourceText = text
                    if !parsed.isEmpty {
                        draft.scenes = max(parsed.count, draft.scenes)
                    }
                    dismiss()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, OT.gutter)
            .padding(.top, 16)

            Form {
                Section {
                    HStack {
                        Text("Paste from clipboard")
                            .font(.otHeadline)
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            let pasted = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !pasted.isEmpty { text = pasted }
                        }
                        .buttonBorderShape(.capsule)
                        .tint(OT.accent)
                    }

                    TextField("Or paste or type sides here...", text: $text, axis: .vertical)
                        .lineLimit(6...14)

                    Button { showImporter = true } label: {
                        Label("Import a PDF or text file", systemImage: "doc")
                    }

                    Button { openScanner() } label: {
                        Label("Scan the pages", systemImage: "doc.viewfinder")
                    }
                } footer: {
                    Text("Sides are parsed on your iPhone into character dialogue lines and scenes.")
                }

                if reading {
                    Section {
                        HStack { ProgressView(); Text("Reading pages…") }
                    }
                }

                if !text.isEmpty {
                    Section("Detected from sides") {
                        if !parsed.isEmpty {
                            LabeledContent("Scenes", value: "\(parsed.count)")
                            LabeledContent("Your lines (\(draft.role.isEmpty ? "Your role" : draft.role))", value: "\(parsed.flatMap(\.lines).filter(\.isMine).count)")
                            LabeledContent("Total character lines", value: "\(parsed.flatMap(\.lines).count)")
                        } else {
                            Text("No character lines recognised yet. Cues should be in CAPS (e.g. “MAYA”) or “Maya: dialogue”.")
                                .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if draft.hasSides {
                text = draft.sourceText
            } else {
                text = ""
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            if let extracted = NoticeOCR.extractText(fromFileAt: url) { text = extracted }
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                reading = true
                Task {
                    let recognized = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run { text = recognized; reading = false }
                }
            }
            .ignoresSafeArea()
        }
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
        }
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true } else { scannerUnavailable = true }
    }
}

// MARK: - 6.2 Missing details

struct MissingDetailsView: View {
    @Environment(AppStore.self) private var store
    @State private var picked: Date = .now.addingTimeInterval(86400)
    @State private var requestedFields: [String] = []
    @State private var showSidesSheet = false

    private var missing: [String] { store.auditionDraft.missingRequiredDetails }
    private var canContinue: Bool {
        !store.auditionDraft.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.auditionDraft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var missingSubtitle: String {
        if missing.isEmpty { return "Everything needed is ready." }
        if missing.count == 1 { return "I couldn't find the \(missing[0]) in the notice. Add it to continue." }
        if missing.count == 2 { return "I couldn't find the \(missing[0]) and \(missing[1]) in the notice. Add what you know to continue." }
        let allButLast = missing.dropLast().joined(separator: ", ")
        return "I couldn't find the \(allButLast), and \(missing.last!) in the notice. Add what you know to continue."
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            InContentNavHeader(backLabel: "Auditions", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(missing.isEmpty ? "All set" : missing.count == 1 ? "One thing missing" : "A few details missing")
                        .font(.otLargeTitle)
                    Text(missingSubtitle)
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Project name", text: $store.auditionDraft.project)
                            .textInputAutocapitalization(.words)
                        TextField("Your role", text: $store.auditionDraft.role)
                            .textInputAutocapitalization(.words)
                        HStack {
                            Text("When is it due?").font(.otHeadline)
                            Spacer()
                            DatePicker("Due date", selection: $picked, in: Date.now...)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    }
                    .padding(16).otCard(radius: 20)

                    SectionLabel(text: "Script Sides")
                    let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                    if parsedScenes.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OT.accent)
                                .frame(width: 34, height: 34)
                                .background(OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No sides attached yet")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Optional · for reader track & lines")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Button("Add sides") {
                                showSidesSheet = true
                            }
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(OT.accentSoft, in: Capsule())
                            .fixedSize()
                        }
                        .padding(14)
                        .otCard(radius: 20)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(parsedScenes.count) scene\(parsedScenes.count == 1 ? "" : "s") · \(parsedScenes.flatMap(\.lines).count) lines")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Ready for lines & reader")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Button("Replace") {
                                showSidesSheet = true
                            }
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accentSoft, in: Capsule())
                            .fixedSize()
                        }
                        .padding(14)
                        .otCard(radius: 20)
                    }

                    Button("Choose a different notice") {
                        store.pop()
                        store.showAddAudition = true
                    }
                    .buttonStyle(.plain)
                    .font(.otCallout)
                    .foregroundStyle(OT.accent)
                    .padding(.top, 8)
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button(store.auditionDraft.hasSides ? "Continue" : "Continue without sides") {
                if store.auditionDraft.due == nil { store.auditionDraft.due = picked }
                store.push(.noticeReview)
            }
            .buttonStyle(.otPrimary)
            .disabled(!canContinue)
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 10)
            .background(OT.bgCanvas)
        }
        .sheet(isPresented: $showSidesSheet) {
            AddDraftSidesSheet(draft: $store.auditionDraft)
        }
        .onAppear {
            let req = store.auditionDraft.missingRequiredDetails
            requestedFields = req.isEmpty ? ["project", "role", "due date"] : req
            if let due = store.auditionDraft.due { picked = due }
        }
    }
}

// MARK: - 6c Here's what they want (review + save)

struct NoticeReviewView: View {
    @Environment(AppStore.self) private var store
    @State private var readerAudioPlan: AddAuditionFlow.ReaderAudioPlan = .recordNow
    @State private var showSidesSheet = false

    private var hasReaderLines: Bool {
        !store.auditionDraft.role.isEmpty && ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
            .contains { $0.lines.contains { !$0.isMine } }
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            InContentNavHeader(backLabel: store.auditionsPath.contains(.missingDetails) ? "Back" : "Auditions", onBack: { store.pop() })
                .padding(.horizontal, OT.gutter)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Here's what they want").font(.otLargeTitle)
                    Text(store.auditionDraft.asks.isEmpty
                         ? "No recording requirements were detected. Review the details, then save."
                         : "\(store.auditionDraft.asks.count) requirement\(store.auditionDraft.asks.count == 1 ? "" : "s") found in the email. Tap any line to change it, then save.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)

                    SectionLabel(text: "Due")
                    if let due = store.auditionDraft.due {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.otTitle)
                            Text(due.formatted(date: .omitted, time: .shortened)).font(.otHeadline).foregroundStyle(OT.due)
                        }
                    } else {
                        DatePicker("Due", selection: Binding(get: { store.auditionDraft.due ?? .now.addingTimeInterval(86400) }, set: { store.auditionDraft.due = $0 })).labelsHidden()
                    }

                    SectionLabel(text: "Sides & Scenes")
                    let parsedScenes = ScriptParser.parseScenes(from: store.auditionDraft.sourceText, myRole: store.auditionDraft.role)
                    if parsedScenes.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OT.accent)
                                .frame(width: 34, height: 34)
                                .background(OT.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No sides attached yet")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Optional · for reader track & lines")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Button("Add sides") {
                                showSidesSheet = true
                            }
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(OT.accentSoft, in: Capsule())
                            .fixedSize()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OT.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(parsedScenes.count) scene\(parsedScenes.count == 1 ? "" : "s") · \(parsedScenes.flatMap(\.lines).count) lines")
                                    .font(.otHeadline)
                                    .foregroundStyle(OT.labelPrimary)
                                Text("Ready for lines & reader")
                                    .font(.otFootnote)
                                    .foregroundStyle(OT.labelSecondary)
                            }
                            Spacer()
                            Button("Replace") {
                                showSidesSheet = true
                            }
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OT.accentSoft, in: Capsule())
                            .fixedSize()
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    SectionLabel(text: "They asked for")
                    if !store.auditionDraft.aiGuidance.isEmpty {
                        Label(store.auditionDraft.aiGuidance, systemImage: "sparkles")
                            .font(.otCallout).foregroundStyle(OT.labelSecondary)
                            .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                        field("person.2", "\(store.auditionDraft.role.isEmpty ? "Role" : store.auditionDraft.role) · \(store.auditionDraft.scenes) scenes", "Your lines found")
                        ForEach(store.auditionDraft.asks, id: \.self) { ask in field(symbol(for: ask), ask, "") }
                    }

                    Group {
                        TextField("Project", text: $store.auditionDraft.project)
                        TextField("Role", text: $store.auditionDraft.role)
                        TextField("Casting office", text: $store.auditionDraft.castingOffice)
                        Stepper("Scenes: \(store.auditionDraft.scenes)", value: $store.auditionDraft.scenes, in: 0...6)
                    }
                    .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if hasReaderLines {
                        SectionLabel(text: "Reader audio")
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Add the other character’s lines now, or record them from the scene later.")
                                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
                            Picker("Reader audio", selection: $readerAudioPlan) {
                                Text("Record now").tag(AddAuditionFlow.ReaderAudioPlan.recordNow)
                                Text("Add later").tag(AddAuditionFlow.ReaderAudioPlan.later)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, OT.gutter)
                .padding(.top, 14)
                .padding(.bottom, 100)
            }
        }
        .otCanvas()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button(hasReaderLines && readerAudioPlan == .recordNow ? "Save and add reader audio" : "Save and start") {
                saveAudition()
            }
            .buttonStyle(.otPrimary)
            .padding(.horizontal, OT.gutter).padding(.bottom, 8)
            .background(OT.bgCanvas)
        }
        .sheet(isPresented: $showSidesSheet) {
            AddDraftSidesSheet(draft: $store.auditionDraft)
        }
        .task {
            if store.auditionDraft.aiGuidance.isEmpty && !store.auditionDraft.sourceText.isEmpty {
                let guidance = await OnDeviceIntelligence.noticeGuidance(store.auditionDraft.sourceText, parsed: store.auditionDraft)
                if let guidance {
                    store.auditionDraft.aiGuidance = guidance
                }
            }
        }
    }

    private func saveAudition() {
        let audition = store.auditionDraft.makeAudition()
        store.add(audition)
        store.tab = .auditions
        if readerAudioPlan == .recordNow,
           let firstScene = audition.scenes.indices.first(where: { !audition.scenes[$0].lines.filter({ !$0.isMine }).isEmpty }) {
            store.auditionsPath = [.auditionDetail(audition.id), .reader(audition.id, sceneIndex: firstScene)]
            store.continueAfterAdd = nil
        } else {
            store.auditionsPath = [.auditionDetail(audition.id)]
            store.continueAfterAdd = audition.id
        }
        store.auditionDraft = .blank
        requestNotificationsIfFirstAudition()
    }

    private func requestNotificationsIfFirstAudition() {
        guard store.auditions.count == 1 else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    private func field(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(OT.labelSecondary)
            Text(title).font(.otHeadline)
            if !detail.isEmpty { Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary) }
        }
    }

    private func symbol(for ask: String) -> String {
        switch ask {
        case "Slate first": "person.text.rectangle"
        case "Landscape": "iphone.landscape"
        case "Full length": "figure.stand"
        default: ask.hasPrefix("Under") ? "timer" : "paperplane"
        }
    }
}

// MARK: - S4 Notice couldn't be read

struct NoticeErrorView: View {
    var onRetry: () -> Void
    var onScan: () -> Void
    var onType: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(OT.warning)
            Text("We couldn't read this notice").font(.otLargeTitle)
            Text("No readable text was found — it may be a photo without text, blurry, or very small print. Nothing was lost — pick how to continue.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Button(action: onRetry) { IconRow(symbol: "arrow.clockwise", title: "Try again", detail: "Go back and pick the photo, scan or file again") }.buttonStyle(.plain)
            Button(action: onScan) { IconRow(symbol: "doc.viewfinder", title: "Scan the pages instead", detail: "Clearer than a screenshot") }.buttonStyle(.plain)
            Button(action: onType) { IconRow(symbol: "keyboard", title: "Type the details", detail: "Name, role and due date — 30 seconds") }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}
