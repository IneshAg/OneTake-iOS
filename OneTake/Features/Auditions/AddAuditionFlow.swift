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
    @State private var draft = NoticeParser.parse(SampleNotice.text)
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
                    case .couldNotRead: NoticeErrorView(onRetry: { path = [.reading] }, onScan: { showScanner = true }, onType: { path = [.review] })
                    }
                }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                showScanner = false
                if !pages.isEmpty { notice = SampleNotice.text; path = [.reading] }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .plainText, .rtf]) { result in
            if case .success = result { notice = SampleNotice.text; path = [.reading] } else { path = [.couldNotRead] }
        }
        .onChange(of: photoItem) { _, item in if item != nil { notice = SampleNotice.text; path = [.reading] } }
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

                if let clip = Clipboard.castingNotice ?? Optional(SampleNotice.text) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.on.clipboard").foregroundStyle(OT.accent)
                                .frame(width: 36, height: 36).background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading) {
                                Text("On your clipboard").font(.otHeadline)
                                Text("Northlight Casting · The Last Summer").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                        }
                        Text("“\(clip.prefix(110))…”").font(.otCallout).foregroundStyle(OT.labelSecondary).lineLimit(3)
                        Button("Paste and set up") { notice = clip; path.append(.reading) }.buttonStyle(.otPrimary)
                    }
                    .padding(16)
                    .background(OT.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                SectionLabel(text: "Or bring it in")
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { way("photo", "Photo") }
                    Button { showScanner = true } label: { way("doc.viewfinder", "Scan") }
                    Button { showFileImporter = true } label: { way("folder", "File") }
                    Button { draft = NoticeParser.Draft.blank; path.append(.review) } label: { way("keyboard", "Type it") }
                }
                .buttonStyle(.plain)

                Label("Faster: Share from Mail or WhatsApp to OneTake", systemImage: "square.and.arrow.up")
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
        dismiss()
        store.tab = .auditions
        store.auditionsPath = [.auditionDetail(audition.id)]
        requestNotificationsIfFirstAudition()
    }

    /// Deferred permission: the first time a due date actually exists to remind about, not during onboarding.
    private func requestNotificationsIfFirstAudition() {
        guard store.auditions.count == 1 else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }
}

// MARK: - Notice parsing (on-device, rule-based placeholder for the real parser)

enum SampleNotice {
    static let text = """
    Hi Kabir, we'd love a self-tape for ARJUN in THE LAST SUMMER (feature). Please send by Fri 9 Oct, 10am. \
    Slate first, landscape, include a full-length shot. Sides attached (2 scenes). Under 3 minutes total. \
    Upload to Actors Access, named Last_First_Role.
    """
}

enum NoticeParser {
    struct Draft: Hashable {
        var project = ""
        var role = ""
        var projectType = "Feature film"
        var due: Date?
        var scenes = 2
        var asks: [String] = []
        var destination: Destination = .actorsAccess

        static let blank = Draft()

        func makeAudition() -> Audition {
            var pieces: [Piece] = [
                .init(kind: .headshot, title: "Headshot", detail: "Front", isDone: false),
                .init(kind: .slate, title: "Slate", detail: "Name, height, city", isDone: false)
            ]
            for i in 0..<max(scenes, 1) { pieces.append(.init(kind: .scene, title: "Scene \(i + 1)", detail: "", isDone: false)) }
            return Audition(project: project.isEmpty ? "Untitled audition" : project, projectType: projectType, role: role.isEmpty ? "Role" : role,
                            roleSize: "Lead", castingOffice: "Northlight Casting", due: due ?? .now.addingTimeInterval(3 * 86400),
                            asks: asks, pieces: pieces, scenes: Array(SampleData.lastSummer.scenes.prefix(scenes)),
                            destination: destination, status: .due)
        }
    }

    static func parse(_ text: String) -> Draft {
        var d = Draft()
        let lower = text.lowercased()
        if lower.contains("last summer") { d.project = "The Last Summer" }
        if lower.contains("arjun") { d.role = "Arjun" }
        if lower.contains("fri 9 oct") { d.due = SampleData.lastSummer.due }
        if lower.contains("slate") { d.asks.append("Slate first") }
        if lower.contains("landscape") { d.asks.append("Landscape") }
        if lower.contains("full-length") || lower.contains("full length") { d.asks.append("Full length") }
        if lower.contains("under 3") { d.asks.append("Under 3 min") }
        if lower.contains("actors access") { d.asks.append("Actors Access"); d.destination = .actorsAccess }
        return d
    }
}

// MARK: - 6.1 Reading the notice

struct NoticeReadingView: View {
    let notice: String
    var onDone: (NoticeParser.Draft) -> Void
    @State private var found = 0
    private let rows = [("Project", "The Last Summer"), ("Your role", "Arjun"), ("Due", "Fri 9 Oct, 10:00 AM"), ("Sides", "2 scenes"), ("What they asked for", "7 things")]

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
            onDone(NoticeParser.parse(notice))
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
                }

                SectionLabel(text: "They asked for")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                    field("person.2", "\(draft.role) · \(draft.scenes) scenes", "Your lines found")
                    ForEach(draft.asks, id: \.self) { ask in field(symbol(for: ask), ask, "") }
                }

                Group {
                    TextField("Project", text: $draft.project)
                    TextField("Role", text: $draft.role)
                    Stepper("Scenes: \(draft.scenes)", value: $draft.scenes, in: 0...6)
                }
                .padding(14).background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 100)
        }
        .otCanvas()
        .safeAreaInset(edge: .bottom) {
            Button("Save audition", action: onSave).buttonStyle(.otPrimary)
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
