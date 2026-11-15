import SwiftUI
import UIKit
import VisionKit

// MARK: - Document scanner (VisionKit, UIKit-only)

/// "Scan the pages" for printed sides. Returns recognised page images.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        private var didComplete = false

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        private func finish(_ controller: VNDocumentCameraViewController, with pages: [UIImage]) {
            guard !didComplete else { return }
            didComplete = true
            controller.delegate = nil
            DispatchQueue.main.async { [onFinish] in
                onFinish(pages)
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let count = scan.pageCount
            var pages: [UIImage] = []
            pages.reserveCapacity(count)
            for i in 0..<count {
                autoreleasepool {
                    let raw = scan.imageOfPage(at: i)
                    pages.append(NoticeOCR.normalizedScanImage(raw))
                }
            }
            finish(controller, with: pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            finish(controller, with: [])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finish(controller, with: [])
        }
    }
}
