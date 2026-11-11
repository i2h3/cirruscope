// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `MediaCaptureDecision` is how the app answers a page asking for the camera or the microphone: by granting it without a prompt of the web view's own, or by leaving it to that prompt.
///
/// Two origins are asked about, and both must be the server's.
/// WebKit documents the one it passes as the page's, and the frame whose script asked has an origin of its own: a frame is not held to the rule that keeps navigations on the server, so one from another origin can sit inside the server's own page.
/// Requiring both makes the answer the same whichever of the two WebKit means by the page.
enum MediaCaptureDecision {
    /// `grant` means the page and the frame asking are both the connected server's, so the web view asks the person nothing of its own.
    case grant

    /// `prompt` means either of them is anything else, or no server is connected, so the web view asks the person as it would without the app.
    case prompt

    /// `forRequest(page:frame:connectedTo:)` is the decision for a request from a page and a frame with the given origins, in an app connected to the server at `serverAddress`, or to none when that is `nil`.
    static func forRequest(page: (scheme: String, host: String, port: Int), frame: (scheme: String, host: String, port: Int), connectedTo serverAddress: URL?) -> MediaCaptureDecision {
        guard let serverAddress else {
            return .prompt
        }

        guard isOrigin(page, of: serverAddress) else {
            return .prompt
        }

        guard isOrigin(frame, of: serverAddress) else {
            return .prompt
        }

        return .grant
    }

    /// `isOrigin(_:of:)` reports whether `origin`, spelled as WebKit spells it, is the origin of `serverAddress`.
    private static func isOrigin(_ origin: (scheme: String, host: String, port: Int), of serverAddress: URL) -> Bool {
        guard origin.scheme.isEmpty == false else {
            return false
        }

        guard origin.host.isEmpty == false else {
            return false
        }

        let port = origin.port == 0 ? "" : ":\(origin.port)"

        guard let address = URL(string: "\(origin.scheme)://\(origin.host)\(port)") else {
            return false
        }

        return SameOriginURL.isSameOrigin(address, as: serverAddress)
    }
}
