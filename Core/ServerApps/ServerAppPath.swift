// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppPath` reads a URL as a path on one Nextcloud server, in the single normalized form two such paths can be compared in.
enum ServerAppPath {
    /// `relativeComponents(of:on:)` is `url`'s path components within `serverAddress`'s own web root, with an `index.php` segment removed, or `nil` when `url` does not address that server at all.
    static func relativeComponents(of url: URL, on serverAddress: URL) -> [String]? {
        guard SameOriginURL(path: url.absoluteString, relativeTo: serverAddress) != nil else {
            return nil
        }

        var components = Self.components(of: url)
        let root = Self.components(of: serverAddress)

        guard components.starts(with: root) else {
            return nil
        }

        components.removeFirst(root.count)

        if components.first == "index.php" {
            components.removeFirst()
        }

        return components
    }

    /// `appPathsByRootRoute` maps the first component of a route an app registers at the server's own root to the path of the app that owns it.
    private static let appPathsByRootRoute = [
        "call": ["apps", "spreed"],
    ]

    /// `canonicalComponents(of:on:)` is the path of the *app* `url` belongs to, which is its own path except where a root route stands in for one.
    static func canonicalComponents(of url: URL, on serverAddress: URL) -> [String]? {
        guard let components = relativeComponents(of: url, on: serverAddress) else {
            return nil
        }

        guard let first = components.first else {
            return components
        }

        guard let appPath = appPathsByRootRoute[first] else {
            return components
        }

        return appPath
    }

    /// `appID(of:on:)` is the Nextcloud app identifier `url` addresses on `serverAddress` — the `<id>` in `/apps/<id>/…` — or `nil` when it addresses no app.
    static func appID(of url: URL, on serverAddress: URL) -> String? {
        guard let components = canonicalComponents(of: url, on: serverAddress) else {
            return nil
        }

        guard components.count >= 2 else {
            return nil
        }

        guard components[0] == "apps" else {
            return nil
        }

        return components[1]
    }

    /// `components(of:)` splits a URL's path into its non-empty segments, left percent-encoded.
    ///
    /// Encoded rather than decoded so a segment carrying an escaped separator stays one segment, and so both sides of a comparison are spelled the way the server spelled them.
    private static func components(of url: URL) -> [String] {
        url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
