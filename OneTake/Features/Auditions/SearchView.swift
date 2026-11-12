import SwiftUI

// MARK: - Search (tab-bar search)

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.isSearching) private var isSearching
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
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0)) // ot-lint:allow
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
                                OTScheduleRow(
                                    eyebrow: a.status == .sent ? "SENT" : a.due.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                                    value: a.status == .sent ? (a.sentDate?.otDayMonth ?? "") : a.dueRemaining.compactSummary,
                                    title: a.project,
                                    detail: "\(a.role) · due \(a.due.otDue)"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !query.isEmpty && !lineHits.isEmpty {
                    Section("In your sides") {
                        ForEach(lineHits) { hit in
                            Button { store.push(.prepare(hit.auditionID, sceneIndex: hit.sceneNumber - 1)) } label: {
                                OTScheduleRow(
                                    eyebrow: "SC \(hit.sceneNumber)",
                                    value: hit.character.capitalized,
                                    title: "“\(hit.text)”",
                                    detail: hit.detail
                                )
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
                                if let id = p.auditionID, let scene = p.sceneIndex,
                                   store.audition(id)?.scenes.indices.contains(scene) == true {
                                    store.push(.runLines(id, sceneIndex: scene))
                                } else if p.scene != nil {
                                    store.promotePracticePiece(p.id)
                                    store.push(.standalonePractice(p.id))
                                }
                            } label: {
                                OTScheduleRow(
                                    eyebrow: "PRACTICE",
                                    value: "\(p.linesLearned)/\(p.linesTotal)",
                                    title: p.title,
                                    detail: p.detail
                                )
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
        .searchable(text: Bindable(store).searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search auditions, sides, practice...")
        .toolbar(isSearching ? .hidden : .visible, for: .tabBar) // ot-lint:allow
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
