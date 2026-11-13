import SwiftUI
import PhotosUI

struct HeadshotsView: View {
    /// Set when opened from an audition's checklist, so the screen can continue to its next step.
    var auditionID: Audition.ID? = nil
    @Environment(AppStore.self) private var store
    @State private var adjustItem: HeadshotAdjustItem?
    @State private var previewItem: HeadshotViewerItem?
    @State private var pickAngle: String?
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isFraming = false
    @State private var framingPreset: HeadshotPreset = .theatrical

    /// Counted from the real files on disk for this specific audition or profile
    private var taken: Int {
        HeadshotStore.taken(auditionID: auditionID).count
    }

    private var profileTaken: Int {
        HeadshotStore.taken(auditionID: nil).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                topCalloutCard

                slotsGrid

                photoActionsBar
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationTitle(auditionID != nil ? "Audition Headshots" : "Default Headshots")
        .navigationBarTitleDisplayMode(.inline)
        .otBottomBar {
            bottomBarContent
        }
        .id(store.headshotVersion)
        .onAppear {
            store.syncHeadshotPieces()
            if ProcessInfo.processInfo.arguments.contains("-testHeadshotAdjust") {
                adjustItem = HeadshotAdjustItem(key: "front", title: "Front", isProfile: false, auditionID: auditionID)
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem, let key = pickAngle else { return }
            let title = key == "front" ? "Front" : key == "left" ? "Left profile" : "Right profile"
            let isProfile = (key == "left" || key == "right")
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        HeadshotStore.save(image, key: key, auditionID: auditionID)
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        Haptics.success()
                        pickerItem = nil
                        pickAngle = nil
                        adjustItem = HeadshotAdjustItem(key: key, title: title, isProfile: isProfile, auditionID: auditionID)
                    }
                }
            }
        }
        .sheet(item: $previewItem) { item in
            HeadshotViewerSheet(item: item, onAdjust: {
                adjustItem = HeadshotAdjustItem(key: item.key, title: item.title, isProfile: item.isProfile, auditionID: item.auditionID)
            })
        }
        .sheet(item: $adjustItem) { item in
            HeadshotAdjustSheet(item: item)
        }
    }

    @ViewBuilder
    private var topCalloutCard: some View {
        if let auditionID {
            if taken > 0 {
                let crop = savedCropRatio(for: "front", auditionID: auditionID)
                OTCallout(
                    systemImage: "checkmark.circle.fill",
                    title: "Saved for this audition",
                    message: "\(taken) of 3 headshots ready · Crop \(crop)",
                    tint: OT.success
                ) {
                    Button(role: .destructive) {
                        HeadshotStore.removeAuditionHeadshots(for: auditionID)
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        Haptics.warning()
                    } label: {
                        Label("Remove audition headshots", systemImage: "trash")
                    }
                    .buttonStyle(.ot(.destructive, size: .small))
                }
            } else {
                let isOpt = store.audition(auditionID)?.pieces.first(where: { $0.kind == .headshot })?.isOptional ?? false
                OTCallout(
                    systemImage: "info.circle.fill",
                    title: isOpt ? "Headshots are optional" : "Audition headshots",
                    message: isOpt
                        ? "You can skip headshots, attach your default profile photo, or take a new one."
                        : "Required for this package. Attach your default profile photo or take new ones.",
                    tint: OT.accent
                ) {
                    if profileTaken > 0 {
                        Button {
                            HeadshotStore.copyProfileHeadshots(to: auditionID)
                            store.headshotVersion += 1
                            store.syncHeadshotPieces()
                            Haptics.success()
                        } label: {
                            Label("Attach default profile photo", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.ot(.secondary, size: .small))
                    }
                }
            }
        } else {
            OTCallout(
                systemImage: "person.crop.square.fill",
                title: "Default profile headshots",
                message: "These are your default actor headshots. Auditions can attach them or use their own photos.",
                tint: OT.accent
            )
        }
    }

    private var slotsGrid: some View {
        HStack(spacing: OTSpace.s) {
            HeadshotSlotTile(
                title: "Front",
                done: HeadshotStore.exists(key: "front", auditionID: auditionID),
                big: true,
                auditionID: auditionID,
                onAdjust: {
                    adjustItem = HeadshotAdjustItem(key: "front", title: "Front", isProfile: false, auditionID: auditionID)
                },
                onInspect: {
                    previewItem = HeadshotViewerItem(key: "front", title: "Front", isProfile: false, auditionID: auditionID)
                },
                onPick: {
                    pickAngle = "front"
                    showPicker = true
                }
            )
            .frame(maxWidth: .infinity)

            VStack(spacing: OTSpace.s) {
                HeadshotSlotTile(
                    title: "Left profile",
                    done: HeadshotStore.exists(key: "left", auditionID: auditionID),
                    big: false,
                    auditionID: auditionID,
                    onAdjust: {
                        adjustItem = HeadshotAdjustItem(key: "left", title: "Left profile", isProfile: true, auditionID: auditionID)
                    },
                    onInspect: {
                        previewItem = HeadshotViewerItem(key: "left", title: "Left profile", isProfile: true, auditionID: auditionID)
                    },
                    onPick: {
                        pickAngle = "left"
                        showPicker = true
                    }
                )
                HeadshotSlotTile(
                    title: "Right profile",
                    done: HeadshotStore.exists(key: "right", auditionID: auditionID),
                    big: false,
                    auditionID: auditionID,
                    onAdjust: {
                        adjustItem = HeadshotAdjustItem(key: "right", title: "Right profile", isProfile: true, auditionID: auditionID)
                    },
                    onInspect: {
                        previewItem = HeadshotViewerItem(key: "right", title: "Right profile", isProfile: true, auditionID: auditionID)
                    },
                    onPick: {
                        pickAngle = "right"
                        showPicker = true
                    }
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 280) // ot-lint:allow
    }

    private var photoActionsBar: some View {
        HStack(spacing: OTSpace.s) {
            Button {
                store.camera = .headshot(auditionID: auditionID)
            } label: {
                Label(taken == 0 ? "Camera" : "Retake", systemImage: "camera.fill")
            }
            .buttonStyle(.ot(.secondary, size: .medium))

            PhotoSourceMenu(auditionID: auditionID, size: .medium) { angle in
                pickAngle = angle.rawValue
                showPicker = true
            }

            if taken > 0 {
                OTMenuButton(
                    framingPreset.shortTitle,
                    systemImage: isFraming ? nil : "sparkles",
                    size: .medium
                ) {
                    ForEach(HeadshotPreset.allCases) { preset in
                        Button {
                            framingPreset = preset
                            autoFrameAllHeadshots(preset: preset)
                        } label: {
                            if framingPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Label(preset.title, systemImage: preset.icon)
                            }
                        }
                    }
                }
                .disabled(isFraming)
            }
        }
    }

    @ViewBuilder
    private var bottomBarContent: some View {
        if let auditionID {
            if taken > 0 {
                OTStatusLine(
                    .success,
                    "Headshots saved on this iPhone",
                    detail: nextStepAfterHeadshots.map { "Next: \($0)" }
                )
            }
            Button(continueButtonTitle) {
                handleContinue(auditionID)
            }
            .buttonStyle(.otPrimary)
        } else {
            Button(taken == 0 ? "Take with Camera" : "Done") {
                if taken == 0 {
                    store.camera = .headshot(auditionID: nil)
                } else {
                    store.pop()
                }
            }
            .buttonStyle(.otPrimary)
        }
    }

    private func autoFrameAllHeadshots(preset: HeadshotPreset = .theatrical) {
        isFraming = true
        let keys = HeadshotStore.taken(auditionID: auditionID).map(\.key)
        let originals = keys.compactMap { key in HeadshotStore.loadOriginal(key: key, auditionID: auditionID).map { (key, $0) } }
        Task.detached(priority: .userInitiated) {
            let framed = originals.compactMap { key, image in
                let isProfile = (key == "left" || key == "right")
                return ImageFramer.crop(image, preset: preset, isProfile: isProfile).map { (key, $0) }
            }
            await MainActor.run {
                for (key, image) in framed { HeadshotStore.replace(image, key: key, auditionID: auditionID) }
                store.headshotVersion += 1
                isFraming = false
                if framed.isEmpty { Haptics.warning() } else { Haptics.success() }
            }
        }
    }

    private func savedCropRatio(for key: String, auditionID: Audition.ID?) -> String {
        guard let image = HeadshotStore.load(key: key, auditionID: auditionID), image.size.height > 0 else { return "4:5" }
        let ratio = image.size.width / image.size.height
        let known: [(CGFloat, String)] = [(4.0 / 5.0, "4:5"), (3.0 / 4.0, "3:4"), (1.0, "1:1")]
        return known.first(where: { abs($0.0 - ratio) < 0.035 })?.1 ?? "Custom"
    }

    private func nextPieceAfterHeadshot(in audition: Audition) -> Piece? {
        audition.pieces.first { $0.kind != .headshot && !$0.isDone }
    }

    private var continueButtonTitle: String {
        guard let auditionID else { return "Continue" }
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasPackage = store.currentPath.contains {
            if case .package(let id) = $0, id == auditionID { return true }
            return false
        }

        if hasPreview {
            return taken > 0 ? "Back to preview" : "Skip & back to preview"
        } else if hasTapeCheck {
            return taken > 0 ? "Back to tape check" : "Skip & back to tape check"
        } else if hasPackage {
            return taken > 0 ? "Back to package" : "Skip & back to package"
        } else {
            guard let audition = store.audition(auditionID) else {
                return taken > 0 ? "Continue" : "Skip & continue"
            }
            guard !audition.isPackageReady, let next = nextPieceAfterHeadshot(in: audition) else { return "Continue to preview" }
            switch next.kind {
            case .slate: return taken > 0 ? "Continue to slate" : "Skip headshots · go to slate"
            case .fullLength: return taken > 0 ? "Continue to full-body shot" : "Skip headshots · go to full-body shot"
            case .scene: return taken > 0 ? "Continue to \(next.title)" : "Skip headshots · go to \(next.title)"
            case .headshot: return "Continue to preview"
            }
        }
    }

    private var nextStepAfterHeadshots: String? {
        guard let auditionID, let audition = store.audition(auditionID) else { return nil }
        guard !audition.isPackageReady, let next = nextPieceAfterHeadshot(in: audition) else { return "Preview" }
        switch next.kind {
        case .headshot: return "Preview"
        case .slate: return "slate"
        case .fullLength: return "full-body shot"
        case .scene: return next.title
        }
    }

    private func handleContinue(_ id: Audition.ID) {
        store.syncPieces()

        // If we came from Preview, pop back to Preview
        if store.currentPath.contains(where: {
            if case .preview(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.preview(id))
            return
        }

        // If we came from Tape Check, pop back to Tape Check
        if store.currentPath.contains(where: {
            if case .tapeCheck(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.tapeCheck(id))
            return
        }

        // If we came from Package, pop back to Package
        if store.currentPath.contains(where: {
            if case .package(let targetID) = $0, targetID == id { return true }
            return false
        }) {
            store.popTo(.package(id))
            return
        }

        guard let a = store.audition(id) else { return }

        // Advance to the next unfinished piece after headshots
        if let next = nextPieceAfterHeadshot(in: a) {
            store.pop()

            switch next.kind {
            case .slate:
                store.camera = .shoot(id, start: .slate)
            case .fullLength:
                store.camera = .shoot(id, start: .fullLength)
            case .scene:
                let idx = store.sceneIndex(for: next, in: id)
                store.camera = .shoot(id, scene: idx)
            case .headshot:
                break
            }
            return
        }

        // If all required pieces are completed or no more pieces, advance to Preview
        if store.currentPath.contains(.auditionDetail(id)) {
            store.popTo(.auditionDetail(id))
        } else {
            store.popToRoot()
        }
        store.push(.preview(id))
    }
}
