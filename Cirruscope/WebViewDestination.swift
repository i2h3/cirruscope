// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `WebViewDestination` is who should handle an address the embedded web view is about to navigate to: the web view itself, or the rest of the system.
///
/// The web view is the connected Nextcloud server's interface and nothing else. A page on another site displayed inside it would borrow the app's window and the trust that goes with it while being none of the app's business, and — because the web view carries the account's session — it is also the thing that must never be pointed somewhere the account's credentials could follow. So anything that is not the connected server is handed over, and the two apps ask that question here so they cannot come to different answers about it.
/// Origin decides it, not host. A different port or a plain-HTTP spelling of the same machine is a different site, and a rule written on hosts alone would wave both through — which is exactly how an app password can end up sent to a service that merely shares a machine with the server.
/// A scheme is the second half of the question, and the reason this is not simply a same-origin test. Most addresses that are not the server are pages, and a browser is where a page belongs; but a document also navigates to addresses that only mean something inside itself — `about:blank` between loads, a `blob:` or `data:` URL it minted, a `javascript:` link — and handing one of those to the system would be meaningless at best. Those stay with the web view, and everything else is offered to the system, which is what lets a `tel:` or `mailto:` link reach the app that can actually act on it.
/// Whether the system can in fact open what it is offered is not decided here, that being a question about the machine rather than about the address. Both apps ask their own platform and fall back to letting the web view try.
enum WebViewDestination {
    /// `webView` means the address is the connected server's, or is one only a document can make sense of, and the navigation should be allowed to proceed.
    case webView

    /// `system` means the address belongs to some other site or application, and should be offered to the system rather than displayed in the app.
    case system

    /// `documentSchemes` are the schemes a document uses on itself, which no other application could act on.
    ///
    /// `about:` is where a web view sits between loads, `blob:` and `data:` address bytes the document itself minted, `javascript:` is code rather than a location, and `file:` is a local path a remote page has no business sending anyone to. Every one of them is meaningful only inside WebKit, so every one of them stays there.
    private static let documentSchemes: Set<String> = ["about", "blob", "data", "javascript", "file"]

    /// `of(_:connectedTo:)` is who should handle `url` for an app connected to the server at `serverAddress`.
    static func of(_ url: URL, connectedTo serverAddress: URL) -> WebViewDestination {
        guard SameOriginURL(path: url.absoluteString, relativeTo: serverAddress) == nil else {
            return .webView
        }

        guard let scheme = url.scheme?.lowercased() else {
            return .webView
        }

        guard Self.documentSchemes.contains(scheme) == false else {
            return .webView
        }

        return .system
    }
}
