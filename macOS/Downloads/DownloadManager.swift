// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import WebKit

/// `DownloadManager` is the app-wide facility that coordinates every file download, decoupled from the user interface as issue #23 requires.
@MainActor
final class DownloadManager: NSObject {
    /// `shared` is the process-wide coordinator, retained for the app's lifetime so it can safely serve as the `weak` delegate of every `WKDownload`.
    static let shared = DownloadManager()

    /// `logger` records download coordination under the `DownloadManager` category; it is not `private` because `DownloadManager+WKDownloadDelegate` logs the transfer callbacks from a separate file.
    let logger = Logger(for: DownloadManager.self)

    /// `downloads` is the in-memory history of downloads for the current run, newest last, exposed read-only so only the coordinator mutates it.
    private(set) var downloads: [Download] = []

    /// `reservedDestinations` holds destination URLs that `uniqueDestination(for:)` has handed to in-flight transfers but that WebKit has not yet written to disk, so two downloads picking the same suggested name in the same instant receive distinct URLs instead of colliding on one.
    private var reservedDestinations: Set<URL> = []

    /// `handle(_:)` adopts `wkDownload`, records it, and starts coordinating it.
    func handle(_ wkDownload: WKDownload) {
        wkDownload.delegate = self

        let download = Download(wkDownload)
        downloads.append(download)

        logger.info("Handling download \(download.displayName)")
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        NotificationCenter.default.post(name: .downloadDidStart, object: nil)
    }

    /// `cancel(_:)` stops an in-progress `download` and marks it `cancelled`.
    func cancel(_ download: Download) {
        logger.notice("Cancelling download \(download.displayName)")
        download.wkDownload?.cancel { _ in }
        download.state = .cancelled

        releaseReservation(for: download)
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
    }

    /// `model(for:)` returns the `Download` that wraps `wkDownload`, matching by object identity, or `nil` if none is tracked.
    func model(for wkDownload: WKDownload) -> Download? {
        downloads.first { $0.wkDownload === wkDownload }
    }

    /// `releaseReservation(for:)` frees the destination URL that `uniqueDestination(for:)` reserved for `download` once its transfer reaches a terminal state, so a later download can reuse that name if the file was never written.
    func releaseReservation(for download: Download) {
        guard let destinationURL = download.destinationURL else {
            return
        }

        reservedDestinations.remove(destinationURL)
    }

    /// `uniqueDestination(for:)` returns a file URL in the user's Downloads folder for `suggestedFilename` that does not yet exist, appending a ` (1)`, ` (2)`, … suffix to the name as needed.
    func uniqueDestination(for suggestedFilename: String) -> URL {
        let directory = URL.downloadsDirectory
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let base = directory.appending(component: name)
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent

        var candidate = base
        var counter = 1

        // Advance past any name already on disk or reserved by another in-flight transfer, then reserve the one
        // chosen: WebKit creates the destination file asynchronously after this returns, so without the reservation
        // two downloads that pick the same suggested name in the same instant would both see it free and collide.
        while isTaken(candidate) {
            let numberedName = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = directory.appending(component: numberedName)
            counter += 1
        }

        reservedDestinations.insert(candidate)
        return candidate
    }

    /// `isTaken(_:)` reports whether `url` is unavailable as a download destination — either a file already exists there or another in-flight transfer has reserved it via `uniqueDestination(for:)`.
    private func isTaken(_ url: URL) -> Bool {
        reservedDestinations.contains(url) || FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
