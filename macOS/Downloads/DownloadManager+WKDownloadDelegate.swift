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
            logger.debug("Posting a completion notification for \(model.displayName)")
            UserNotifier.shared.postDownloadFinished(filename: model.displayName, fileURL: destinationURL)
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
}
