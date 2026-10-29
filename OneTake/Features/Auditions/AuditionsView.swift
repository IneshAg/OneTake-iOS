import SwiftUI

/// 05 Auditions — light, single column library with an "Active ▾" filter and swipe actions.
struct AuditionsView: View {
    enum Filter: String, CaseIterable, Identifiable { case active = "Active", dueThisWeek = "Due this week", sent = "Sent", all = "All"; var id: String { rawValue } }

    @Environment(AppStore.self) private var store
    @State private var filter: Filter = .active
    @State private var pendingDelete: Audition?

    private var items: [Audition] {
        switch filter {
        case .active:      store.active + store.sent
        case .dueThisWeek: store.active.filter { $0.due.timeIntervalSinceNow < 7 * 86400 }
        case .sent:        store.sent
        case .all:         store.auditions
        }
    }

    var body: some View {
        Group {
            if store.auditions.isEmpty {
                EmptyAuditionsView { store.showAddAudition = true }
            } else {
                List {
                    ForEach(items) { audition in
                        Button { store.push(.auditionDetail(audition.id)) } label: {
                            AuditionCard(audition: audition) { store.continueAudition(audition.id) }
                        }
                        .buttonStyle(PressableCardStyle())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: OT.gutter, bottom: 6, trailing: OT.gutter))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = audition } label: { Label("Delete", systemImage: "trash") }
                            if audition.status != .sent {
                                Button { store.markSent(audition.id); Haptics.success() } label: { Label("Mark sent", systemImage: "paperplane.fill") }
                                    .tint(OT.success)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .safeAreaInset(edge: .top) { header }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete “\(pendingDelete?.project ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let a = pendingDelete { store.deleteAudition(a.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Its slate, reader track and any takes are removed from this iPhone. Your headshots stay in Profile.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Auditions")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Spacer()
            Menu {
                Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
            } label: {
                Label(filter.rawValue, systemImage: "chevron.down").labelStyle(TrailingIconLabelStyle())
                    .font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(OT.fillField, in: Capsule())
            }
            Button { store.showAddAudition = true } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OT.labelOnAccent)
                    .frame(width: 44, height: 44).background(OT.accent, in: Circle())
            }
            .accessibilityLabel("Add an audition")
            ProfileButton { store.showProfile = true }
        }
        .padding(.horizontal, OT.gutter)
        .padding(.bottom, 6)
        .background(OT.bgCanvas)
    }

}

// MARK: - Audition card (v2/Audition Card · Due / Ready / Sent)

struct AuditionCard: View {
    let audition: Audition
    var onNext: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HeadshotImage(realKey: "front").id(store.headshotVersion)
                .frame(width: 88, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(audition.project).font(.otHeadline).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    if audition.status == .sent {
                        Label("Sent", systemImage: "paperplane.fill")
                            .font(.otCaption.weight(.semibold)).foregroundStyle(OT.success)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(OT.success.opacity(0.14), in: Capsule())
                    }
                }
                Text("\(audition.projectType) · \(audition.role)").font(.otFootnote).foregroundStyle(OT.labelSecondary)

                if audition.status == .sent {
                    Label("\(audition.sentDate?.otDayMonth ?? "")" + (audition.shareLinkTimeLeft.map { " · link active \($0)" } ?? ""),
                          systemImage: audition.shareLink != nil ? "link" : "paperplane")
                        .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                } else {
                    ReadinessDashes(done: audition.readyCount, total: audition.totalCount)
                    statusLine
                    Divider().padding(.vertical, 2)
                    Button(action: onNext) {
                        HStack(spacing: 6) {
                            Image(systemName: nextSymbol).font(.footnote)
                            Text("Next: \(audition.nextAction)").font(.otSubhead.weight(.semibold))
                            Image(systemName: "arrow.right").font(.footnote)
                        }
                        .foregroundStyle(OT.accent)
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .otCard(radius: 20)
    }

    @ViewBuilder private var statusLine: some View {
        if audition.status == .ready {
            Label("Ready to send · due \(audition.due.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle")
                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.success)
        } else {
            Label("Due \(audition.due.formatted(.relative(presentation: .named)))", systemImage: "clock")
                .font(.otFootnote.weight(.semibold)).foregroundStyle(OT.due)
        }
    }

    private var nextSymbol: String {
        switch audition.nextPiece?.kind {
        case .headshot: "person.crop.square"
        case .slate, .fullLength, .scene: audition.nextPiece?.title == "Watch it once" ? "paperplane.fill" : "video.fill"
        case nil: "paperplane.fill"
        }
    }
}

// MARK: - 5a Empty

struct EmptyAuditionsView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("onetake-empty-auditions-illustration")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 300)
                .accessibilityLabel("No auditions yet illustration")

            Text("No auditions yet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(OT.labelPrimary)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OT.gutter)
    }
}

// MARK: - Search (tab-bar search)

struct SearchView: View {
    @Environment(AppStore.self) private var store
    private var query: String { store.searchQuery }

    enum SearchScope: String, CaseIterable, Identifiable {
        case all = "All"
        case auditions = "Auditions"
        case practice = "Practice"
        var id: String { rawValue }
    }

    @State private var scope: SearchScope = .all
    @State private var hasSetInitialScope = false

    struct LineHit: Identifiable {
        let id: UUID
        let auditionID: Audition.ID
        let sceneNumber: Int
        let character: String
        let text: String
        let detail: String
    }

    private var lineHits: [LineHit] {
        var out: [LineHit] = []
        for a in store.auditions {
            for s in a.scenes {
                for l in s.lines where l.text.localizedCaseInsensitiveContains(query) {
                    out.append(LineHit(id: UUID(), auditionID: a.id, sceneNumber: s.number, character: l.character, text: l.text, detail: "\(a.project) · \(s.title)"))
                }
            }
        }
        return out
    }

    var body: some View {
        List {
            // Scope selector
            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            }

            // Auditions & Sides
            if scope == .all || scope == .auditions {
                let auditionHits = store.auditions.filter {
                    query.isEmpty || $0.project.localizedCaseInsensitiveContains(query) || $0.role.localizedCaseInsensitiveContains(query) || $0.castingOffice.localizedCaseInsensitiveContains(query)
                }
                if !auditionHits.isEmpty {
                    Section("Auditions") {
                        ForEach(auditionHits) { a in
                            Button { store.push(.auditionDetail(a.id)) } label: {
                                ScheduleRow(eyebrow: a.status == .sent ? "SENT" : a.due.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                                            value: a.status == .sent ? (a.sentDate?.otDayMonth ?? "") : "\(a.hoursLeft)h",
                                            title: a.project, detail: "\(a.role) · due \(a.due.otDue)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !query.isEmpty && !lineHits.isEmpty {
                    Section("In your sides") {
                        ForEach(lineHits) { hit in
                            Button { store.push(.prepare(hit.auditionID, sceneIndex: hit.sceneNumber - 1)) } label: {
                                ScheduleRow(eyebrow: "SC \(hit.sceneNumber)", value: hit.character.capitalized, title: "“\(hit.text)”", detail: hit.detail)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Practice Section
            if scope == .all || scope == .practice {
                let practiceHits = store.practice.filter {
                    query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
                }
                if !practiceHits.isEmpty {
                    Section("Practice") {
                        ForEach(practiceHits) { p in
                            Button {
                                // The piece's own audition and scene — not whichever audition happens to be first.
                                if let id = p.auditionID, let scene = p.sceneIndex,
                                   store.audition(id)?.scenes.indices.contains(scene) == true {
                                    store.push(.runLines(id, sceneIndex: scene))
                                }
                            } label: {
                                ScheduleRow(eyebrow: "PRACTICE", value: "\(p.linesLearned)/\(p.linesTotal)", title: p.title, detail: p.detail)
                            }
                            .buttonStyle(.plain)
                        }
                        if query.isEmpty || "warm-up cold read off-book slate".localizedCaseInsensitiveContains(query) {
                            Button { store.push(.practiceSetup) } label: {
                                ScheduleRow(eyebrow: "SETUP", value: "New", title: "Practise a scene", detail: "Cold read, off-book check, or slate run")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Search")
        .onAppear {
            if !hasSetInitialScope {
                hasSetInitialScope = true
                switch store.lastActiveTab {
                case .practice:  scope = .practice
                case .profile:   scope = .all
                case .auditions: scope = .auditions
                case .search:    scope = .all
                }
            }
        }
    }
}
