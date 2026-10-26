import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import UserNotifications

/// 06 Add an audition → 6.1 Reading the notice → (6.2 One thing missing) → 6c Here's what they want → 7.0 Detail (0 of 4)
struct AddAuditionFlow: View {
    enum Step: Hashable { case reading, missingDate, review, couldNotRead }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var notice = ""
    @State private var draft = NoticeParser.Draft.blank
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var scannerUnavailable = false

    var body: some View {
        NavigationStack(path: $path) {
            capture
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .reading:      NoticeReadingView(notice: notice) { result in draft = result; path.append(result.due == nil ? .missingDate : .review) }
                    case .missingDate:  MissingDateView(draft: $draft) { path.append(.review) }
                    case .review:       NoticeReviewView(draft: $draft) { save() }
                    case .couldNotRead: NoticeErrorView(onRetry: { path = [] }, onScan: { openScanner() }, onType: { draft = .blank; path = [.review] })
                    }
                }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                guard !pages.isEmpty else { return }
                Task {
                    let text = await NoticeOCR.recognizeText(in: pages)
                    await MainActor.run {
                        if !NoticeOCR.looksReadable(text) { path = [.couldNotRead] }
                        else { notice = text; path = [.reading] }
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
                if let text, NoticeOCR.looksReadable(text) { notice = text; path = [.reading] }
                else { path = [.couldNotRead] }
            case .failure:
                path = [.couldNotRead]
            }
        }
        .alert("Scanning isn't available here", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs the iPhone camera. Use Photo or File instead.")
        }
        // Something shared to OneTake from another app (see ShareInbox): read it like any other notice.
        .task { await readSharedNotice() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    await MainActor.run { path = [.couldNotRead] }
                    return
                }
                let text = await NoticeOCR.recognizeText(in: [image])
                await MainActor.run {
                    if !NoticeOCR.looksReadable(text) { path = [.couldNotRead] }
                    else { notice = text; path = [.reading] }
                }
            }
        }
    }

    private func openScanner() {
        // VisionKit's scanner needs a real camera; it isn't available in the Simulator.
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
        if !NoticeOCR.looksReadable(text) { path = [.couldNotRead] } else { notice = text; path = [.reading] }
    }

    // MARK: 06 capture-first sheet

    private var capture: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Add an audition").font(.otTitle)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }

                // The system paste button reads the clipboard only when tapped, so opening this sheet
                // no longer peeks at it (which raised iOS's "Allow Paste" prompt every time).
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(OT.accent)
                            .frame(width: 36, height: 36).background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading) {
                            Text("Copied the notice?").font(.otHeadline)
                            Text("Paste the email or message — OneTake reads it here").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { @MainActor in
                            guard !text.isEmpty else { return }
                            notice = text
                            path = [.reading]
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .tint(OT.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OT.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                SectionLabel(text: "Or bring it in")
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { way("photo", "Photo") }
                    Button { openScanner() } label: { way("doc.viewfinder", "Scan") }
                    Button { showFileImporter = true } label: { way("folder", "File") }
                    Button { draft = NoticeParser.Draft.blank; path.append(.review) } label: { way("keyboard", "Type it") }
                }
                .buttonStyle(.plain)

                Label("Faster: in Mail or WhatsApp, Share → OneTake", systemImage: "square.and.arrow.up")
                    .font(.otFootnote).foregroundStyle(OT.accent)
                Label("Read on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
            }
            .padding(OT.gutter)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func way(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(OT.labelPrimary)
                .frame(width: 52, height: 52).background(OT.fillField, in: Circle())
            Text(title).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let audition = draft.makeAudition()
        store.add(audition)
        store.tab = .auditions
        // Straight on to the first step; the overview sits underneath only as the back target.
        store.auditionsPath = [.auditionDetail(audition.id)]
        store.continueAfterAdd = audition.id
        dismiss()
        requestNotificationsIfFirstAudition()
    }

    /// Deferred permission: the first time a due date actually exists to remind about, not during onboarding.
    private func requestNotificationsIfFirstAudition() {
        guard store.auditions.count == 1 else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
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
        var scenes = 1
        var asks: [String] = []
        var destination: Destination = .actorsAccess
        /// The real recognised text this draft came from — kept so `makeAudition()` can parse real
        /// sides out of it instead of substituting a canned scene.
        var sourceText = ""

        static let blank = Draft()

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
        if let office = labeled(["casting director", "casting office", "casting company", "casting", "agency"], in: text) {
            d.castingOffice = office
        }
        if let explicit = detectSceneCount(in: text) {
            d.scenes = max(explicit, 1)
        } else {
            d.scenes = max(ScriptParser.parseScenes(from: rawText, myRole: d.role).count, 1)
        }

        func ask(_ s: String) { if !d.asks.contains(s) { d.asks.append(s) } }
        if lower.contains("slate") { ask("Slate first") }
        if lower.contains("landscape") || lower.contains("horizontal") { ask("Landscape") }
        if lower.contains("full-length") || lower.contains("full length") || lower.contains("full body") || lower.contains("full-body") {
            ask("Full length")
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
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'*_.,;:-"))
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

    /// Labeled "Role:" first, then phrases like "for the role of Maya in …", then the old ALL-CAPS cue.
    private static func detectRole(in text: String) -> String? {
        if let v = labeled(["role", "character", "part", "playing"], in: text) { return v.capitalized }
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

    /// Labeled "Project:" / "Title:", then a quoted title, then "in THE LAST SUMMER (feature)".
    private static func detectProject(in text: String) -> String? {
        if let v = labeled(["project", "title", "production", "film", "series", "show"], in: text) { return v.capitalized }
        if let v = firstMatch(#""([^"\n]{3,60})""#, in: text) { return clean(v).capitalized }
        if let v = firstMatch(#"\bin\s+([A-Z][A-Z0-9'&, \-]{2,40}?)(?:\s*[\(.,]|\s+by\s|$)"#, in: text) {
            let cleaned = clean(v)
            return cleaned.isEmpty ? nil : cleaned.capitalized
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

// MARK: - 6.1 Reading the notice

struct NoticeReadingView: View {
    let notice: String
    var onDone: (NoticeParser.Draft) -> Void
    @State private var found = 0
    private let draft: NoticeParser.Draft

    init(notice: String, onDone: @escaping (NoticeParser.Draft) -> Void) {
        self.notice = notice
        self.onDone = onDone
        self.draft = NoticeParser.parse(notice)
    }

    private var rows: [(String, String)] {
        [
            ("Project", draft.project.isEmpty ? "Not found — type it in" : draft.project),
            ("Your role", draft.role.isEmpty ? "Not found — type it in" : draft.role),
            ("Due", draft.due.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not found — pick a date"),
            ("Sides", draft.scenes == 1 ? "1 scene" : "\(draft.scenes) scenes"),
            ("What they asked for", "\(draft.asks.count) things")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading the notice…").font(.otLargeTitle)
            Text("Usually a few seconds. Nothing leaves your iPhone.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            Text(notice).font(.otCallout).foregroundStyle(OT.labelSecondary).lineLimit(4)
                .padding(14).background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            SectionLabel(text: "Found so far").padding(.top, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.otBody)
                        Text(i < found ? row.1 : "reading…").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    }
                    Spacer()
                    if i < found { Image(systemName: "checkmark").foregroundStyle(OT.accent) } else { ProgressView() }
                }
                .padding(.vertical, 6)
                Divider()
            }
            Spacer()
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
        .task {
            for i in 1...rows.count { try? await Task.sleep(for: .milliseconds(450)); found = i; Haptics.tick() }
            try? await Task.sleep(for: .milliseconds(300))
            onDone(draft)
        }
    }
}

// MARK: - 6.2 One thing missing

struct MissingDateView: View {
    @Binding var draft: NoticeParser.Draft
    var onContinue: () -> Void
    @State private var picked: Date = .now.addingTimeInterval(86400)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One thing missing").font(.otLargeTitle)
            Text("Everything else is filled in from the notice.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            VStack(alignment: .leading, spacing: 12) {
                Text("When is it due?").font(.otHeadline)
                Text("The notice didn't give a date.").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                DatePicker("Due", selection: $picked).labelsHidden()
            }
            .padding(16).otCard(radius: 20)
            Spacer()
            Button("Continue") { draft.due = picked; onContinue() }.buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
    }
}

// MARK: - 6c Here's what they want (review + save)

struct NoticeReviewView: View {
    @Binding var draft: NoticeParser.Draft
    var onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Here's what they want").font(.otLargeTitle)
                Text("\(draft.asks.count + 1) things found in the email. Tap any line to change it, then save.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)

                SectionLabel(text: "Due")
                if let due = draft.due {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.otTitle)
                        Text(due.formatted(date: .omitted, time: .shortened)).font(.otHeadline).foregroundStyle(OT.due)
                    }
                } else {
                    DatePicker("Due", selection: Binding(get: { draft.due ?? .now.addingTimeInterval(86400) }, set: { draft.due = $0 })).labelsHidden()
                }

                SectionLabel(text: "They asked for")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                    field("person.2", "\(draft.role.isEmpty ? "Role" : draft.role) · \(draft.scenes) scenes", "Your lines found")
                    ForEach(draft.asks, id: \.self) { ask in field(symbol(for: ask), ask, "") }
                }

                Group {
                    TextField("Project", text: $draft.project)
                    TextField("Role", text: $draft.role)
                    TextField("Casting office", text: $draft.castingOffice)
                    Stepper("Scenes: \(draft.scenes)", value: $draft.scenes, in: 0...6)
                }
                .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !draft.sourceText.isEmpty && ScriptParser.parseScenes(from: draft.sourceText, myRole: draft.role).isEmpty {
                    Label("Couldn't make out character lines from this — the checklist still gets created, and you can add sides once you have clean pages.", systemImage: "info.circle")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 100)
        }
        .otCanvas()
        .safeAreaInset(edge: .bottom) {
            Button("Save and start", action: onSave).buttonStyle(.otPrimary)
                .padding(.horizontal, OT.gutter).padding(.bottom, 8)
                .background(OT.bgCanvas)
        }
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
    }
}
