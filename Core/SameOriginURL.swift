// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `SameOriginURL` is a location a Nextcloud server named, proven to be on that same server before anything is sent to it.
struct SameOriginURL: Sendable {
    /// `logger` records every refusal under the `SameOriginURL` category.
    private static let logger = Logger(for: SameOriginURL.self)

    /// `url` is the absolute location to request, known to be on the same origin as the server that named it.
    let url: URL

    /// `init?(path:relativeTo:)` resolves `path` against `serverAddress`, or returns `nil` if it does not stay on that server.
    init?(path: String, relativeTo serverAddress: URL) {
        guard let resolved = URL(string: path, relativeTo: serverAddress)?.absoluteURL else {
            Self.logger.error("Refusing \"\(path, privacy: .public)\": it is not a location at all once resolved against the server address")
            return nil
        }

        guard Self.isSameOrigin(resolved, as: serverAddress) else {
            Self.logger.error("Refusing \"\(path, privacy: .public)\": it resolves to another origin than the connected server's, so nothing will be sent to it")
            return nil
        }

        url = resolved
    }

    /// `init?(components:relativeTo:)` is the address of a path *the app itself knows*, appended to `serverAddress`, or `nil` when it cannot be built.
    init?(components: [String], relativeTo serverAddress: URL) {
        guard components.isEmpty == false else {
            Self.logger.error("Refusing an empty list of path components, which would address the server's own root")
            return nil
        }

        guard components.contains(where: \.isEmpty) == false else {
            Self.logger.error("Refusing path components containing an empty one, which would produce a doubled separator")
            return nil
        }

        guard components.contains(where: { $0 == "." || $0 == ".." }) == false else {
            Self.logger.error("Refusing path components containing a dot segment, which would climb out of the instance's web root while staying on its origin")
            return nil
        }

        var address = serverAddress

        for component in components {
            address = address.appending(component: component)
        }

        self.init(path: address.absoluteString, relativeTo: serverAddress)
    }

    /// `isSameOrigin(_:as:)` reports whether two URLs address the same scheme, host, and port.
    static func isSameOrigin(_ url: URL, as other: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let otherScheme = other.scheme?.lowercased(), scheme == otherScheme else {
            return false
        }

        guard let host = url.host()?.lowercased(), let otherHost = other.host()?.lowercased(), host == otherHost else {
            return false
        }

        return port(of: url) == port(of: other)
    }

    /// `port(of:)` is a URL's port, filled in from its scheme where it was left out.
    private static func port(of url: URL) -> Int? {
        guard let port = url.port else {
            switch url.scheme?.lowercased() {
                case "https":
                    return 443
                case "http":
                    return 80
                default:
                    return nil
            }
        }

        return port
    }
}
