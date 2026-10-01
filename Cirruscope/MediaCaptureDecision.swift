// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `MediaCaptureDecision` is how the app answers a page asking for the camera or the microphone: by granting it without a prompt of the web view's own, or by leaving it to that prompt.
///
/// Only the connected server is granted anything, and the server means its origin — scheme, host and port together — compared by the same rule `SameOriginURL` applies before the app password is attached to anything.
/// Host alone once decided it, so a plain-HTTP listener or a differently-ported service on the server's machine was handed the camera and the microphone unasked.
/// Everything else is prompted for rather than refused, so the person can still allow a site they trust.
/// The system's own permission is a separate question, asked by macOS once per app, and nothing here answers it.
///
/// Two origins are asked about, and both must be the server's.
/// WebKit documents the one it passes as the page's, and the frame whose script asked has an origin of its own: a frame is not held to the rule that keeps navigations on the server, so one from another origin can sit inside the server's own page.
/// Requiring both makes the answer the same whichever of the two WebKit means by the page.
///
/// Each origin is taken as `WKSecurityOrigin` spells it, which was measured rather than assumed and is pinned by `SecurityOriginProbe`: the host comes lowercased, an IPv6 address in brackets and an internationalized name in its ASCII form, and the port is `0` whenever it is the scheme's own, even where the page's address spelled it out.
/// An opaque origin, such as a sandboxed frame's, arrives with an empty scheme and host, and is never the server's.
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
    ///
    /// It spells the origin back out as an address and asks `SameOriginURL`, so there is one comparison of origins in the app rather than a second one free to differ from it; a port of `0` is left out of that address, which is how a URL says "the scheme's own".
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
