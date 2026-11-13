import SwiftUI
import PhotosUI

struct HeadshotAdjustItem: Identifiable {
    let key: String
    let title: String
    let isProfile: Bool
    var auditionID: UUID? = nil
    var id: String { "\(key)-\(auditionID?.uuidString ?? "profile")" }
}

struct HeadshotAdjustSheet: View {
    let item: HeadshotAdjustItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    @State private var originalImage: UIImage?
    @State private var selectedPreset: HeadshotPreset = .theatrical
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var photoItem: PhotosPickerItem?
    @State private var isAutoFraming = false
    @State private var saveError = false

    /// Display frame dimensions inside the sheet matching slot proportions or selected preset ratio.
    private func targetFrameSize(for preset: HeadshotPreset) -> CGSize {
        let maxW: CGFloat = 300 // ot-lint:allow
        let maxH: CGFloat = 380 // ot-lint:allow
        let r = preset.ratio(isProfile: item.isProfile)
        if r > (maxW / maxH) {
            return CGSize(width: maxW, height: maxW / r)
        } else {
            return CGSize(width: maxH * r, height: maxH)
        }
    }

    private var frameSize: CGSize {
        targetFrameSize(for: selectedPreset)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Viewport area
                ZStack {
                Color.black.ignoresSafeArea() // ot-lint:allow

                if let img = originalImage {
                    let baseScale = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
                    let currentZoom = max(1.0, min(zoom * pinchScale, 4.0))
                    let effectiveOffset = clampOffset(
                        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height),
                        zoomFactor: currentZoom
                    )

                    // Clamped crop frame
                    ZStack {
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: img.size.width * baseScale * currentZoom,
                                   height: img.size.height * baseScale * currentZoom) // ot-lint:allow
                            .offset(effectiveOffset)

                        // Rule of thirds subtle grid guides
                        gridLines

                        // Corner crop brackets
                        cornerBrackets
                    }
                    .frame(width: frameSize.width, height: frameSize.height) // ot-lint:allow
                    .clipShape(RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5) // ot-lint:allow
                    )
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { val in dragOffset = val.translation }
                                .onEnded { val in
                                    offset = clampOffset(
                                        CGSize(width: offset.width + val.translation.width, height: offset.height + val.translation.height),
                                        zoomFactor: zoom
                                    )
                                    dragOffset = .zero
                                },
                            MagnificationGesture()
                                .onChanged { val in pinchScale = val }
                                .onEnded { val in
                                    zoom = max(1.0, min(zoom * val, 4.0))
                                    pinchScale = 1.0
                                    offset = clampOffset(offset, zoomFactor: zoom)
                                }
                        )
                    )
                } else {
                    ProgressView()
                        .tint(.white) // ot-lint:allow
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom control panel
            VStack(spacing: OTSpace.s) {
                OTMenuButton(
                    "Auto-frame · \(selectedPreset.title)",
                    systemImage: "sparkles",
                    size: .medium
                ) {
                    ForEach(HeadshotPreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                            autoFrame(preset: preset, animated: true)
                        } label: {
                            if selectedPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Label(preset.title, systemImage: preset.icon)
                            }
                        }
                    }
                }
                .padding(.horizontal, OTSpace.gutter)

                Text("Choose a preset, then pinch or drag the photo to fine-tune its size and position.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OTSpace.l)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: OTSpace.s) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            zoom = 1.0
                            offset = .zero
                            dragOffset = .zero
                            pinchScale = 1.0
                        }
                        Haptics.tick()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.ot(.secondary, size: .medium))

                    OTMenuButton(
                        "Replace",
                        systemImage: "arrow.triangle.2.circlepath",
                        size: .medium
                    ) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            dismiss()
                            store.camera = .headshot(auditionID: item.auditionID)
                        } label: {
                            Label("Take with Camera", systemImage: "camera")
                        }
                    }
                }
                .padding(.horizontal, OTSpace.gutter)
                .padding(.bottom, OTSpace.xs)
            }
            .padding(.top, OTSpace.m)
            .background(OT.surfaceRaised)
            }
            .navigationTitle("Adjust \(item.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCrop() }
                }
            }
        }
        .onAppear { loadPhoto() }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let upright = ImageFramer.normalized(img) {
                    await MainActor.run {
                        HeadshotStore.save(upright, key: item.key, auditionID: item.auditionID)
                        originalImage = upright
                        zoom = 1.0
                        offset = .zero
                        dragOffset = .zero
                        pinchScale = 1.0
                        store.headshotVersion += 1
                        store.syncHeadshotPieces()
                        autoFrame(preset: selectedPreset)
                    }
                }
            }
        }
        .alert("Couldn't save this headshot crop", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original photo is still saved. Try adjusting the crop and saving again.")
        }
    }

    private func loadPhoto() {
        if let raw = HeadshotStore.loadOriginal(key: item.key, auditionID: item.auditionID) ?? HeadshotStore.load(key: item.key, auditionID: item.auditionID),
           let upright = ImageFramer.normalized(raw) {
            originalImage = upright
            autoFrame(preset: selectedPreset, animated: false)
        }
    }

    private func clampOffset(_ raw: CGSize, zoomFactor: CGFloat, customFrame: CGSize? = nil) -> CGSize {
        guard let img = originalImage else { return .zero }
        let target = customFrame ?? frameSize
        let base = max(target.width / img.size.width, target.height / img.size.height)
        let z = max(1.0, min(zoomFactor, 4.0))
        let maxOffX = max(0, (img.size.width * base * z - target.width) / 2)
        let maxOffY = max(0, (img.size.height * base * z - target.height) / 2)
        return CGSize(
            width: min(max(raw.width, -maxOffX), maxOffX),
            height: min(max(raw.height, -maxOffY), maxOffY)
        )
    }

    private func autoFrame(preset: HeadshotPreset? = nil, animated: Bool = true) {
        let targetPreset = preset ?? selectedPreset
        guard let img = originalImage, let cg = img.cgImage else { return }
        let imgSize = CGSize(width: cg.width, height: cg.height)
        let face = ImageFramer.detectSubject(in: cg, size: imgSize, isProfile: item.isProfile)
        let ratio = targetPreset.ratio(isProfile: item.isProfile)
        let rect = ImageFramer.cropRect(imageSize: imgSize, subject: face, ratio: ratio, preset: targetPreset, isProfile: item.isProfile)
        guard rect.width > 0, rect.height > 0 else { return }

        let targetFrame = targetFrameSize(for: targetPreset)
        let base = max(targetFrame.width / img.size.width, targetFrame.height / img.size.height)
        let pointsToPixels = CGFloat(cg.width) / img.size.width
        let targetCropWInPoints = rect.width / pointsToPixels
        let targetZoom = max(1.0, min(targetFrame.width / (targetCropWInPoints * base), 4.0))

        let cropCenterInPoints = CGPoint(x: rect.midX / pointsToPixels, y: rect.midY / pointsToPixels)
        let imageCenterInPoints = CGPoint(x: img.size.width / 2, y: img.size.height / 2)

        let requiredOffsetX = (imageCenterInPoints.x - cropCenterInPoints.x) * base * targetZoom
        let requiredOffsetY = (imageCenterInPoints.y - cropCenterInPoints.y) * base * targetZoom

        let applyTransform = {
            zoom = targetZoom
            offset = clampOffset(CGSize(width: requiredOffsetX, height: requiredOffsetY), zoomFactor: targetZoom, customFrame: targetFrame)
            dragOffset = .zero
            pinchScale = 1.0
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                applyTransform()
            }
            Haptics.tick()
        } else {
            applyTransform()
        }
    }

    private func saveCrop() {
        guard let img = originalImage, let cg = img.cgImage else { saveError = true; return }
        let base = max(frameSize.width / img.size.width, frameSize.height / img.size.height)
        let z = max(1.0, min(zoom, 4.0))
        let effectiveOffset = clampOffset(offset, zoomFactor: z)

        let displayedW = img.size.width * base * z
        let displayedH = img.size.height * base * z

        let imageOriginX = (frameSize.width - displayedW) / 2 + effectiveOffset.width
        let imageOriginY = (frameSize.height - displayedH) / 2 + effectiveOffset.height

        let cropInPointsX = (0 - imageOriginX) / (base * z)
        let cropInPointsY = (0 - imageOriginY) / (base * z)
        let cropInPointsW = frameSize.width / (base * z)
        let cropInPointsH = frameSize.height / (base * z)

        let scaleFactor = CGFloat(cg.width) / img.size.width
        let pixelRect = CGRect(
            x: cropInPointsX * scaleFactor,
            y: cropInPointsY * scaleFactor,
            width: cropInPointsW * scaleFactor,
            height: cropInPointsH * scaleFactor
        ).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))

        guard pixelRect.width > 0, pixelRect.height > 0, let croppedCG = cg.cropping(to: pixelRect) else {
            saveError = true
            return
        }

        let croppedImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
        guard HeadshotStore.replace(croppedImage, key: item.key, auditionID: item.auditionID) else {
            saveError = true
            return
        }
        store.headshotVersion += 1
        store.syncHeadshotPieces()
        Haptics.success()
        dismiss()
    }

    private var gridLines: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 1) // ot-lint:allow
        }
    }

    private var cornerBrackets: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let arm: CGFloat = 16 // ot-lint:allow
            Path { path in
                path.move(to: CGPoint(x: 0, y: arm))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))

                path.move(to: CGPoint(x: w - arm, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: arm))

                path.move(to: CGPoint(x: 0, y: h - arm))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: arm, y: h))

                path.move(to: CGPoint(x: w - arm, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - arm))
            }
            .stroke(Color.white.opacity(0.8), lineWidth: 2.5) // ot-lint:allow
        }
    }
}
