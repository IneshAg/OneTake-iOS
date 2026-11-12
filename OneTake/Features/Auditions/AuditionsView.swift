import SwiftUI

/// 05 Auditions — light, single column library with swipe actions.
struct AuditionsView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDelete: Audition?

    private var items: [Audition] {
        store.active + store.sent
    }

    var body: some View {
        Group {
            if store.auditions.isEmpty {
                EmptyAuditionsView { store.showAddAudition = true }
            } else {
                List {
                    ForEach(items) { audition in
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
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    pendingDelete = (pendingDelete?.id == audition.id ? nil : audition)
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                            if audition.status != .sent {
                                Button { store.markSent(audition.id); Haptics.success() } label: { Label("Mark sent", systemImage: "paperplane.fill") }
                                    .tint(OT.success)
                            }
                        }
                        .contextMenu {
                            if audition.status != .sent {
                                Button { store.markSent(audition.id); Haptics.success() } label: {
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
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .otCanvas()
        .safeAreaInset(edge: .top) { header }
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
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
        .padding(OTSpace.m)
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
        HStack(alignment: .center, spacing: OTSpace.s) {
            Text("Auditions")
                .font(.otLargeTitle)
                .foregroundStyle(OT.labelPrimary)
            Spacer()
            OTIconButton("plus", accessibilityLabel: "Add an audition") {
                store.showAddAudition = true
            }
            ProfileButton { store.showProfile = true }
        }
        .padding(.horizontal, OTSpace.gutter)
        .padding(.bottom, 6) // ot-lint:allow
        .background(OT.bgCanvas)
    }
}

// MARK: - 5a Empty

struct EmptyAuditionsView: View {
    var onAdd: () -> Void

    var body: some View {
        OTEmptyState(
            illustration: Image("onetake-empty-auditions-illustration"),
            title: "No auditions yet",
            message: "Add your sides or casting notice to start preparing.",
            action: ("Add audition", onAdd)
        )
    }
}
