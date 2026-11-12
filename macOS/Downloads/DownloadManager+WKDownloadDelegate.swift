// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import WebKit

/// `DownloadManager`'s conformance to `WKDownloadDelegate` drives each transfer: it picks a non-clobbering destination in the user's Downloads folder, records the outcome on the matching `Download`, and announces changes so the UI refreshes.
extension DownloadManager: WKDownloadDelegate {
    @objc(download:decideDestinationUsingResponse:suggestedFilename:completionHandler:)
    func download(_ download: WKDownload, decideDestinationUsing _: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        logger.debug("Deciding destination for a download with suggested filename \(suggestedFilename)")

        let destination = uniqueDestination(for: suggestedFilename)

        if let model = model(for: download) {
            model.destinationURL = destination
            model.displayName = destination.lastPathComponent
        } else {
            logger.error("No tracked download matched this transfer while deciding its destination")
        }

        logger.debug("Chose destination \(destination.lastPathComponent); returning it to WebKit")
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        completionHandler(destination)
    }

    @objc(downloadDidFinish:)
    func downloadDidFinish(_ download: WKDownload) {
        logger.debug("Received a download-finished callback")

        guard let model = model(for: download) else {
            logger.error("No tracked download matched the finished transfer; ignoring")
            return
        }

        model.state = .finished
        model.wkDownload = nil

        logger.info("Download finished: \(model.displayName)")

        releaseReservation(for: model)
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)

        if let destinationURL = model.destinationURL {
            let displayName = model.displayName
            Task.detached(priority: .utility) {
                DownloadManager.replaceWithAppWrittenCopy(destinationURL)
                await MainActor.run {
                    Logger(for: DownloadManager.self).debug("Posting a completion notification for \(displayName)")
                    UserNotifier.shared.postDownloadFinished(filename: displayName, fileURL: destinationURL)
                }
            }
        } else {
            logger.debug("Finished download has no recorded destination; skipping the completion notification")
        }
    }

    @objc(download:didFailWithError:resumeData:)
    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        logger.debug("Received a download-failed callback: \(error.localizedDescription)")

        guard let model = model(for: download) else {
            logger.error("No tracked download matched the failed transfer; ignoring")
            return
        }

        // A user-initiated cancel surfaces here as `NSURLErrorCancelled` after `cancel(_:)` already set the state,
        // so leave an explicit cancellation untouched and only record a genuine failure.
        guard model.state != .cancelled else {
            logger.debug("Failure is the user cancellation already recorded for \(model.displayName); leaving its state unchanged")
            model.wkDownload = nil
            NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
            return
        }

        model.state = .failed
        model.error = error
        logger.error("Download failed: \(model.displayName): \(error.localizedDescription)")

        releaseReservation(for: model)
        model.wkDownload = nil
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
    }

    /// Replaces a finished download with a copy the app writes itself, so a downloaded app bundle opens.
    /// WebKit's download process quarantines its file with a record macOS refuses to open and the app's sandbox cannot clear, while a fresh copy carries only the creation marker (`0x82`) every file a sandboxed app writes has.
    /// A file that cannot be replaced stays in place and still counts as downloaded; the failure is only logged.
    nonisolated static func replaceWithAppWrittenCopy(_ url: URL) {
        let logger = Logger(for: DownloadManager.self)
        let fileManager = FileManager.default
        let copy = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).cirruscope-\(UUID().uuidString)")

        do {
            try fileManager.copyItem(at: url, to: copy)
            // `rename(2)` swaps the copy in atomically, so a failure leaves the original in place; `replaceItemAt` would carry the original's quarantine record over.
            guard rename(copy.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            logger.debug("Replaced \(url.lastPathComponent) with an app-written copy to drop WebKit's quarantine record")
        } catch {
            logger.error("Could not replace \(url.lastPathComponent) with an app-written copy: \(error.localizedDescription)")
            try? fileManager.removeItem(at: copy)
        }
    }
}
