// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension answers which of the apps a server offers a given page belongs to, so a surface showing that page can name it.
extension Collection<ServerAppTransferObject> {
    /// `app(for:on:)` is the app whose pages `url` belongs to, or `nil` when it belongs to none of them.
    func app(for url: URL, on serverAddress: URL) -> ServerAppTransferObject? {
        guard let components = ServerAppPath.canonicalComponents(of: url, on: serverAddress) else {
            return nil
        }

        var match: (app: ServerAppTransferObject, depth: Int)?

        for app in self {
            // The server chose this path, so it is resolved through the same type that decides whether it may be
            // requested at all. One that leaves the server cannot describe a page on it either.
            guard let target = SameOriginURL(path: app.href, relativeTo: serverAddress) else {
                continue
            }

            // The literal path, not the canonical one: an `href` is where the app itself is served, so it
            // is never a root route standing in for somewhere else. Canonicalizing it would let an app
            // whose own path began with a mapped segment be rewritten into the app that segment belongs
            // to, and then match every page of it.
            guard let hrefComponents = ServerAppPath.relativeComponents(of: target.url, on: serverAddress) else {
                continue
            }

            // An app claiming the instance root would prefix every URL on the server and so match all of them.
            // No server offers one; this is what keeps a malformed answer from swallowing every other app.
            guard hrefComponents.isEmpty == false else {
                continue
            }

            guard components.starts(with: hrefComponents) else {
                continue
            }

            guard hrefComponents.count > (match?.depth ?? 0) else {
                continue
            }

            match = (app, hrefComponents.count)
        }

        if let match {
            return match.app
        }

        guard let id = ServerAppPath.appID(of: url, on: serverAddress) else {
            return nil
        }

        return first { $0.id == id }
    }
}
