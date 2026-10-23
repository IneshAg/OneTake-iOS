import Foundation

/// "Email or link" delivery: copies the exported tape into the app's iCloud Drive container and asks
/// iCloud to publish it as a download link (`url(forPublishingUbiquitousItemAt:)`). Anyone with the
/// link can download the file — casting doesn't need the app or an Apple account. The actor's own
/// iCloud account is the only account involved; there's no OneTake server.
enum CloudLink {
    enum CloudError: LocalizedError {
        case iCloudUnavailable, uploadFailed(Error?), uploadTimedOut

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                "Sign in to iCloud (Settings → your name) and turn on iCloud Drive to send a link."
            case .uploadFailed(let error):
                "Couldn't upload to iCloud. \(error?.localizedDescription ?? "Check your connection and try again.")"
            case .uploadTimedOut:
                "iCloud is taking too long to upload the tape. Check your connection and try again."
            }
        }
    }

    struct Published {
        let url: URL
        /// When iCloud stops serving the link. iCloud sets this, not the app.
        let expires: Date?
    }

    /// True when the person is signed in to iCloud on this iPhone. Cheap; safe on the main thread.
    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    static func publish(_ fileURL: URL, uploadTimeout: Duration = .seconds(15 * 60)) async throws -> Published {
        // Every file-system call against the ubiquity container can block, so none of it runs on main.
        let work = Task.detached(priority: .userInitiated) { () async throws -> Published in
            let fm = FileManager.default
            guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { throw CloudError.iCloudUnavailable }

            // A fresh folder per send keeps the file name casting expects, and never touches a link
            // that was already sent for an earlier version of the tape.
            let dir = container.appendingPathComponent("Documents/Tapes/\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent(fileURL.lastPathComponent)

            // setUbiquitous *moves* its source, so hand it a copy and keep the local export intact.
            let staging = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileURL.lastPathComponent)")
            try fm.copyItem(at: fileURL, to: staging)
            do {
                try fm.setUbiquitous(true, itemAt: staging, destinationURL: destination)
            } catch {
                try? fm.removeItem(at: staging)
                throw CloudError.uploadFailed(error)
            }

            try await waitForUpload(of: destination, timeout: uploadTimeout)

            var expiration: NSDate?
            let link = try fm.url(forPublishingUbiquitousItemAt: destination, expiration: &expiration)
            return Published(url: link, expires: expiration as Date?)
        }
        // A detached task doesn't inherit cancellation, so forward it — Cancel on the progress screen
        // must stop the upload wait too.
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    /// iCloud uploads in the background; a link can only be published for an item that's uploaded.
    private static func waitForUpload(of url: URL, timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        var url = url
        while true {
            try Task.checkCancellation()
            url.removeAllCachedResourceValues()
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
            if values?.ubiquitousItemIsUploaded == true { return }
            if let error = values?.ubiquitousItemUploadingError { throw CloudError.uploadFailed(error) }
            guard ContinuousClock.now < deadline else { throw CloudError.uploadTimedOut }
            try await Task.sleep(for: .seconds(1))
        }
    }
}
