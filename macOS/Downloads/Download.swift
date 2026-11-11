// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WebKit

/// `Download` is the runtime record of a single file transfer that `DownloadManager` coordinates and `DownloadViewController` displays.
@MainActor
final class Download: Identifiable {
    /// `State` enumerates the mutually exclusive phases a `Download` moves through, which `DownloadTableCellView` maps to the visibility of its stop and reveal buttons and the text it shows.
    enum State {
        /// `inProgress` is the phase while the transfer is running and its bytes are still arriving.
        case inProgress

        /// `finished` is the terminal phase once the file has been fully written to `destinationURL`.
        case finished

        /// `failed` is the terminal phase when the transfer errored, with the underlying error kept in `error`.
        case failed

        /// `cancelled` is the terminal phase after the user stopped the transfer via `DownloadManager.cancel(_:)`.
        case cancelled
    }

    /// `id` uniquely identifies the download so the model can satisfy `Identifiable`.
    let id = UUID()

    /// `progress` is the `Progress` reported by the underlying `WKDownload`, captured at creation so it stays readable after `wkDownload` is released on a terminal state.
    let progress: Progress

    /// `displayName` is the file name shown in the row.
    var displayName: String

    /// `destinationURL` is the location in the user's Downloads folder the file is written to, or `nil` until `DownloadManager` decides it in `download(_:decideDestinationUsing:suggestedFilename:)`.
    var destinationURL: URL?

    /// `state` is the download's current phase, which `DownloadManager` advances and `DownloadTableCellView` renders.
    var state: State = .inProgress

    /// `error` is the failure reported to `download(_:didFailWithError:resumeData:)`, kept for diagnostics when `state` is `failed`.
    var error: (any Error)?

    /// `wkDownload` is the underlying transfer, held strongly because `WKDownload.delegate` is `weak` and nothing else retains it once `WebViewController` hands it off.
    var wkDownload: WKDownload?

    /// `init(_:)` creates a record for `wkDownload`, capturing its `progress` and deriving an initial `displayName` from the request it originated from.
    init(_ wkDownload: WKDownload) {
        self.wkDownload = wkDownload
        progress = wkDownload.progress
        displayName = wkDownload.originalRequest?.url?.lastPathComponent ?? "download"
    }
}
