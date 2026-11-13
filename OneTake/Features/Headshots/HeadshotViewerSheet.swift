import SwiftUI
import PhotosUI

struct HeadshotViewerItem: Identifiable {
    let key: String
    let title: String
    let isProfile: Bool
    var auditionID: UUID? = nil
    var id: String { "view-\(key)-\(auditionID?.uuidString ?? "profile")" }
}

struct HeadshotViewerSheet: View {
    let item: HeadshotViewerItem
    let onAdjust: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var replacePickerItem: PhotosPickerItem?

    private var image: UIImage? {
        HeadshotStore.load(key: item.key, auditionID: item.auditionID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                Color.black.ignoresSafeArea() // ot-lint:allow

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                        .padding(.horizontal, OTSpace.m)
                } else {
                    ProgressView().tint(.white) // ot-lint:allow
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom action bar
            HStack(spacing: OTSpace.s) {
                Button {
                    dismiss()
                    onAdjust()
                } label: {
                    Label("Adjust", systemImage: "crop")
                }
                .buttonStyle(.ot(.secondary, size: .medium))

                OTMenuButton(
                    "Replace",
                    systemImage: "arrow.triangle.2.circlepath",
                    size: .medium
                ) {
                    PhotosPicker(selection: $replacePickerItem, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        dismiss()
                        store.camera = .headshot(auditionID: item.auditionID)
                    } label: {
                        Label("Take with Camera", systemImage: "camera")
                    }
                }

                Button(role: .destructive) {
                    let dir = item.auditionID != nil
                        ? MediaStore.directory("audition_headshots/\(item.auditionID!.uuidString)")
                        : MediaStore.directory("headshots")
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.key).jpg"))
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.key)_original.jpg"))
                    HeadshotStore.clearCache()
                    store.headshotVersion += 1
                    store.syncHeadshotPieces()
                    Haptics.warning()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.ot(.destructive, size: .medium, fullWidth: false))
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.vertical, OTSpace.m)
            .background(OT.surfaceRaised)
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: replacePickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        HeadshotStore.save(img, key: item.key, auditionID: item.auditionID)
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        Haptics.success()
                        dismiss()
                        onAdjust()
                    }
                }
            }
        }
    }
}
