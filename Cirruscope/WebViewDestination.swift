// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `WebViewDestination` is who should handle an address the embedded web view is about to navigate to: the web view itself, or the rest of the system.
enum WebViewDestination {
    /// `webView` means the address is the connected server's, or is one only a document can make sense of, and the navigation should be allowed to proceed.
    case webView

    /// `system` means the address belongs to some other site or application, and should be offered to the system rather than displayed in the app.
    case system

    /// `documentSchemes` are the schemes a document uses on itself, which no other application could act on.
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
