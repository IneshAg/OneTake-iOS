import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Share to OneTake" from Mail, WhatsApp, Safari, Photos or Files. Saves what was shared into the
/// App Group inbox (`ShareInbox`) for the app to set up as an audition the next time it opens —
/// an extension can't open its own app, so the sheet says so instead of pretending.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.save(items) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case saving, saved, nothing, failed }
    @Published private(set) var state: State = .saving

    func save(_ items: [NSExtensionItem]) async {
        guard let folder = ShareInbox.makeItemFolder() else { state = .failed; return }
        var texts: [String] = []
        var fileCount = 0
        for item in items {
            if let body = item.attributedContentText?.string, !body.isEmpty { texts.append(body) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    fileCount += 1
                    _ = await copyFile(provider, type: .pdf, to: folder.appendingPathComponent("file-\(fileCount).pdf"))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    fileCount += 1
                    _ = await copyFile(provider, type: .image, to: folder.appendingPathComponent("file-\(fileCount)"), keepExtension: true)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await loadText(provider) {
                    texts.append(text)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) as? URL {
                    texts.append(url.absoluteString)
                }
            }
        }
        // Mail and WhatsApp often send the same text as both the message body and an attachment.
        var seen = Set<String>()
        let text = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: "\n\n")
        if !text.isEmpty {
            try? text.write(to: folder.appendingPathComponent(ShareInbox.textFileName), atomically: true, encoding: .utf8)
        }
        if ShareInbox.read(folder).isEmpty {
            try? FileManager.default.removeItem(at: folder)
            state = .nothing
        } else {
            state = .saved
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) else { return nil }
        if let string = item as? String { return string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        if let url = item as? URL { return try? String(contentsOf: url, encoding: .utf8) }
        return nil
    }

    /// The shared file only exists for the duration of the callback, so it's copied straight away.
    private func copyFile(_ provider: NSItemProvider, type: UTType, to destination: URL, keepExtension: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { continuation.resume(returning: false); return }
                let dest = keepExtension ? destination.appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension) : destination
                continuation.resume(returning: (try? FileManager.default.copyItem(at: url, to: dest)) != nil)
            }
        }
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            switch model.state {
            case .saving:
                ProgressView()
                Text("Saving to OneTake…").font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Saved to OneTake").font(.title2.bold())
                Text("Open OneTake and it'll set up the audition from this — nothing is uploaded.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .nothing:
                Image(systemName: "questionmark.circle").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Nothing OneTake can read").font(.title2.bold())
                Text("Share the notice's text, a photo or scan of the sides, or a PDF.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .failed:
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                Text("Couldn't save it").font(.title2.bold())
                Text("Open OneTake and add the audition from there instead.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: onDone) {
                Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(model.state == .saving)
        }
        .padding(24)
        .tint(Color(red: 0x5B / 255, green: 0x3E / 255, blue: 0x73 / 255))
    }
}
