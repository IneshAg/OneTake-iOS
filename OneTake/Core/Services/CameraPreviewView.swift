import AVFoundation
import SwiftUI
import UIKit
import OneTakeUI

// MARK: - Preview layer (UIKit)

/// Hosts `AVCaptureVideoPreviewLayer` — not available in SwiftUI — inside a `UIView`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    /// Hands the preview layer to whoever keeps it level (see `CameraController.attachPreview`).
    var onLayer: (@MainActor (AVCaptureVideoPreviewLayer) -> Void)? = nil

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
        onLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.videoGravity = gravity
    }
}

/// Camera background that falls back to a still in the Simulator (no camera there).
struct CameraBackground: View {
    let controller: CameraController
    @State private var focusPoint: CGPoint?
    @State private var focusRingScale: CGFloat = 1.3
    @State private var focusRingOpacity: Double = 0
    @State private var lastFocusPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OT.cameraBg
                #if targetEnvironment(simulator)
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.14), Color(white: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13)) // ot-lint:allow
                            Text("SIMULATOR CAMERA")
                                .font(.system(size: 11, weight: .bold, design: .monospaced)) // ot-lint:allow
                        }
                        .foregroundStyle(Color.white.opacity(0.18)) // ot-lint:allow
                        .padding(.bottom, 130) // ot-lint:allow
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                #else
                CameraPreview(session: controller.session) { layer in controller.attachPreview(layer) }
                #endif

                if let pt = focusPoint {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6) // ot-lint:allow camera focus reticle
                            .stroke(OT.prompterGold, lineWidth: 2)
                            .frame(width: 72, height: 72) // ot-lint:allow camera focus reticle

                        Circle()
                            .fill(OT.prompterGold)
                            .frame(width: 4, height: 4)
                    }
                    .position(pt)
                    .scaleEffect(focusRingScale)
                    .opacity(focusRingOpacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if controller.isExposureLocked {
                    controller.unlockExposure()
                }
                lastFocusPoint = location
                focusPoint = location
                focusRingScale = 1.3
                focusRingOpacity = 1.0
                Haptics.tick()
                controller.focusAndLockExposure(at: location)
                withAnimation(.easeOut(duration: 0.25)) {
                    focusRingScale = 1.0
                }
                withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
                    focusRingOpacity = 0
                }
            }
            .onLongPressGesture(minimumDuration: 0.65) {
                let point = lastFocusPoint ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                focusPoint = point
                focusRingOpacity = 1
                focusRingScale = 1
                controller.lockExposure(at: point)
                Haptics.success()
                withAnimation(.easeOut(duration: 0.35).delay(1.2)) { focusRingOpacity = 0 }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { lastFocusPoint = $0.location }
            )
        }
        .ignoresSafeArea()
    }
}
