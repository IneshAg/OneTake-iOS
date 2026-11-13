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

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let count = scan.pageCount
            var pages: [UIImage] = []
            pages.reserveCapacity(count)
            for i in 0..<count {
                pages.append(scan.imageOfPage(at: i))
            }
            DispatchQueue.main.async { [weak self] in
                self?.onFinish(pages)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            DispatchQueue.main.async { [weak self] in
                self?.onFinish([])
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.onFinish([])
            }
        }
    }
}
