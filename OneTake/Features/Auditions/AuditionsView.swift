import SwiftUI

/// 05 Auditions — light, single column library with swipe actions.
struct AuditionsView: View {
    enum FilterTab: String, CaseIterable, Identifiable {
        case active = "Active"
        case submitted = "Submitted"
        case archived = "Archived"
        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @State private var selectedTab: FilterTab = .active
    @State private var pendingDelete: Audition?

    private var items: [Audition] {
        switch selectedTab {
        case .active: store.active
        case .submitted: store.sent
        case .archived: store.archived
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.auditions.isEmpty {
                EmptyAuditionsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { audition in
                        auditionRow(for: audition)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if items.isEmpty {
                        VStack(spacing: OTSpace.s) {
                            Image(systemName: selectedTab == .active ? "tray" : (selectedTab == .submitted ? "paperplane.circle" : "archivebox"))
                                .font(.otIcon(.xl))
                                .foregroundStyle(OT.labelTertiary)
                            Text("No \(selectedTab.rawValue.lowercased()) auditions")
                                .font(.otHeadline)
                                .foregroundStyle(OT.labelPrimary)
                            Text(selectedTab == .submitted
                                 ? "Auditions you mark as submitted will appear here."
                                 : selectedTab == .archived
                                 ? "Swipe an audition in Active or Submitted to archive it."
                                 : "Tap + to add your next audition.")
                                .font(.otCallout)
                                .foregroundStyle(OT.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, OTSpace.xl)
                            if selectedTab != .active {
                                Button("Show active auditions") {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedTab = .active
                                    }
                                    Haptics.tick()
                                }
                                .buttonStyle(.ot(.secondary, size: .small))
                                .padding(.top, OTSpace.s)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func auditionRow(for audition: Audition) -> some View {
        VStack(spacing: OTSpace.s) {
            Button { store.push(.auditionDetail(audition.id)) } label: {
                AuditionCard(audition: audition) { store.continueAudition(audition.id) }
            }
            .buttonStyle(OTPressStyle(.card))

            if pendingDelete?.id == audition.id {
                inlineDeleteConfirmation(for: audition)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: OTSpace.gutter, bottom: 6, trailing: OTSpace.gutter)) // ot-lint:allow
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            auditionSwipeActions(for: audition)
        }
        .contextMenu {
            auditionContextMenu(for: audition)
        }
    }

    @ViewBuilder
    private func auditionSwipeActions(for audition: Audition) -> some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                pendingDelete = (pendingDelete?.id == audition.id ? nil : audition)
            }
        } label: { Label("Delete", systemImage: "trash") }

        if audition.archived {
            Button {
                store.unarchiveAudition(audition.id)
                Haptics.success()
            } label: {
                Label("Unarchive", systemImage: "arrow.uturn.backward")
            }
            .tint(OT.accent)
        } else {
            Button {
                store.archiveAudition(audition.id)
                Haptics.tick()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(OT.reader)
        }

        if audition.status != .sent && !audition.archived {
            Button {
                store.markSent(audition.id)
                Haptics.success()
            } label: {
                Label("Mark sent", systemImage: "paperplane.fill")
            }
            .tint(OT.success)
        }
    }

    @ViewBuilder
    private func auditionContextMenu(for audition: Audition) -> some View {
        if !audition.archived {
            Button {
                store.archiveAudition(audition.id)
                Haptics.tick()
            } label: {
                Label("Archive audition", systemImage: "archivebox")
            }
        } else {
            Button {
                store.unarchiveAudition(audition.id)
                Haptics.success()
            } label: {
                Label("Unarchive audition", systemImage: "arrow.uturn.backward")
            }
        }
        if audition.status != .sent && !audition.archived {
            Button {
                store.markSent(audition.id)
                Haptics.success()
            } label: {
                Label("Mark sent", systemImage: "paperplane.fill")
            }
        }
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                pendingDelete = audition
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func inlineDeleteConfirmation(for audition: Audition) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.s) {
            HStack(spacing: OTSpace.s) {
                Image(systemName: "trash.fill")
                    .font(.subheadline)
                    .foregroundStyle(OT.danger)
                Text("Delete “\(audition.project)”?")
                    .font(.otHeadline)
                    .foregroundStyle(OT.labelPrimary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        pendingDelete = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OT.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss delete confirmation")
            }

            Text("Its slate, reader track and any takes are removed from this iPhone.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)

            HStack(spacing: OTSpace.s) {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        store.deleteAudition(audition.id)
                        pendingDelete = nil
                    }
                    Haptics.success()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.ot(.destructive, size: .medium))

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        pendingDelete = nil
                    }
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.ot(.secondary, size: .medium))
            }
        }
        .otCard(.grouped)
        .overlay(
            RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                .stroke(OT.danger.opacity(0.35), lineWidth: 1) // ot-lint:allow
        )
        .padding(.horizontal, OTSpace.xxs)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
        ))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OTSpace.xs) {
            HStack(alignment: .center, spacing: OTSpace.s) {
                Text("Auditions")
                    .font(.otLargeTitle)
                    .foregroundStyle(OT.labelPrimary)

                Spacer()

                filterMenu

                OTIconButton("plus", accessibilityLabel: "Add an audition") {
                    store.showAddAudition = true
                }
                ProfileButton { store.showProfile = true }
            }

            if selectedTab != .active {
                activeFilterBadge
            }
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.bottom, OTSpace.s)
        .background(OT.bgCanvas)
    }

    private var filterMenu: some View {
        OTMenuIconButton(
            selectedTab == .active ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill",
            accessibilityLabel: "Filter auditions. Currently showing \(selectedTab.rawValue)",
            tintColor: selectedTab == .active ? nil : OT.accent
        ) {
            Picker("Filter", selection: $selectedTab) {
                ForEach(FilterTab.allCases) { tab in
                    let count = countFor(tab)
                    Label(
                        count > 0 ? "\(tab.rawValue) (\(count))" : tab.rawValue,
                        systemImage: filterSystemImage(for: tab)
                    )
                    .tag(tab)
                }
            }
        }
    }

    private var activeFilterBadge: some View {
        HStack(spacing: OTSpace.xs) {
            OTChip(
                "Showing \(selectedTab.rawValue) (\(countFor(selectedTab)))",
                systemImage: filterSystemImage(for: selectedTab),
                tint: OT.accent
            )
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedTab = .active
                }
                Haptics.tick()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.otIcon(.s))
                    .foregroundStyle(OT.labelTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset to Active auditions")

            Spacer()
        }
        .padding(.top, OTSpace.xxs)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func countFor(_ tab: FilterTab) -> Int {
        switch tab {
        case .active: store.active.count
        case .submitted: store.sent.count
        case .archived: store.archived.count
        }
    }

    private func filterSystemImage(for tab: FilterTab) -> String {
        switch tab {
        case .active: "sparkles"
        case .submitted: "paperplane.fill"
        case .archived: "archivebox.fill"
        }
    }
}

// MARK: - 5a Empty

struct EmptyAuditionsView: View {
    var body: some View {
        OTEmptyState(
            illustration: Image("onetake-empty-auditions-illustration"),
            title: "No auditions yet",
            message: "Add your sides or casting notice to start preparing."
        )
    }
}
