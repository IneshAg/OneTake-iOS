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
            if !store.auditions.isEmpty {
                Picker("Filter auditions", selection: $selectedTab) {
                    ForEach(FilterTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.m)
                .padding(.bottom, OTSpace.s)
            }

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
                .contentMargins(.top, OTSpace.s, for: .scrollContent)
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "No \(selectedTab.rawValue.lowercased()) auditions",
                                systemImage: selectedTab == .active ? "tray" : (selectedTab == .submitted ? "paperplane.circle" : "archivebox")
                            )
                        } description: {
                            Text(selectedTab == .submitted
                                 ? "Auditions you mark as submitted will appear here."
                                 : selectedTab == .archived
                                 ? "Swipe an audition in Active or Submitted to archive it."
                                 : "Tap + to add your next audition.")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .navigationTitle("Auditions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.showAddAudition = true
                } label: {
                    Label("Add an audition", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ProfileButton { store.showProfile = true }
            }
        }
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
