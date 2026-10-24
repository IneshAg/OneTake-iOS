import SwiftUI
import PhotosUI
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

    var body: some View {
        NavigationStack(path: $path) {
            capture
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .reading:      NoticeReadingView(notice: notice) { result in draft = result; path.append(result.due == nil ? .missingDate : .review) }
                    case .missingDate:  MissingDateView(draft: $draft) { path.append(.review) }
                    case .review:       NoticeReviewView(draft: $draft) { save() }
                    case .couldNotRead: NoticeErrorView(onRetry: { path = [.reading] }, onScan: { showScanner = true }, onType: { draft = .blank; path = [.review] })
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
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { path = [.couldNotRead] }
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
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notice = text; path = [.reading] }
                else { path = [.couldNotRead] }
            case .failure:
                path = [.couldNotRead]
            }
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
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { path = [.couldNotRead] }
                    else { notice = text; path = [.reading] }
                }
            }
        }
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
        if text.isEmpty { path = [.couldNotRead] } else { notice = text; path = [.reading] }
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
                    Button { showScanner = true } label: { way("doc.viewfinder", "Scan") }
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
                            role: role.isEmpty ? "Role" : role, roleSize: "Lead", castingOffice: "Casting office",
                            due: due ?? .now.addingTimeInterval(3 * 86400),
                            asks: asks, pieces: pieces, scenes: parsedScenes,
                            destination: destination, status: .due)
        }
    }

    static func parse(_ text: String) -> Draft {
        var d = Draft()
        d.sourceText = text
        let lower = text.lowercased()

        d.due = detectDate(in: text)
        if let role = detectRole(in: text) { d.role = role }
        if let project = detectProject(in: text) { d.project = project }
        d.scenes = max(detectSceneCount(in: text) ?? 1, 1)

        if lower.contains("slate") { d.asks.append("Slate first") }
        if lower.contains("landscape") { d.asks.append("Landscape") }
        if lower.contains("full-length") || lower.contains("full length") { d.asks.append("Full length") }
        if lower.contains("under 3") { d.asks.append("Under 3 min") }
        if lower.contains("feature") { d.projectType = "Feature film" }
        else if lower.contains("series") || lower.contains("episod") { d.projectType = "Series" }
        else if lower.contains("theatre") || lower.contains("theater") { d.projectType = "Theatre" }
        for dest in Destination.allCases where lower.contains(dest.rawValue.lowercased()) {
            d.destination = dest
            d.asks.append(dest.rawValue)
        }
        return d
    }

    /// NSDataDetector finds real dates in arbitrary text — "by Fri 9 Oct, 10am", "due 10/12", etc.
    private static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.first?.date
    }

    /// "self-tape for ARJUN", "reading for the role of MAYA" — the all-caps word(s) right after "for".
    private static func detectRole(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\bfor\s+(?:the\s+role\s+of\s+)?([A-Z][A-Z\-]{1,22})\b"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).capitalized
    }

    /// "in THE LAST SUMMER (feature)" — the capitalised run between "in" and the next punctuation.
    private static func detectProject(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\bin\s+([A-Z][A-Z0-9'&, \-]{2,40}?)(?:\s*[\(.,]|\s+by\s|$)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text) else { return nil }
        let candidate = String(text[r]).trimmingCharacters(in: .whitespaces)
        return candidate.isEmpty ? nil : candidate.capitalized
    }

    /// "Sides attached (2 scenes)" — any "<N> scene(s)" mention.
    private static func detectSceneCount(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s+scenes?"#, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[r])
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
        case "Under 3 min": "timer"
        default: "paperplane"
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
            Text("It looks like an image of a PDF with very small text. Nothing was lost — pick how to continue.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
            Button(action: onRetry) { IconRow(symbol: "arrow.clockwise", title: "Try again", detail: "Reads it once more on this iPhone") }.buttonStyle(.plain)
            Button(action: onScan) { IconRow(symbol: "doc.viewfinder", title: "Scan the pages instead", detail: "Clearer than a screenshot") }.buttonStyle(.plain)
            Button(action: onType) { IconRow(symbol: "keyboard", title: "Type the details", detail: "Name, role and due date — 30 seconds") }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
    }
}
