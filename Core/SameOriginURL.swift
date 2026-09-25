// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `SameOriginURL` is a location a Nextcloud server named, proven to be on that same server before anything is sent to it.
///
/// The proof is the point of the type. A server describes its own resources by path — the navigation endpoint answers `"/apps/files/"` for where an app lives and `"/apps/files/img/app.svg"` for its icon — and both are requested with the user's app password in an `Authorization` header, so that they work on an instance restricting them. Each half of that is reasonable and the combination is not: the path is chosen by the server, so an app that is compromised or simply malicious could name `https://evil.example/x.svg` and be handed the credential by return of post.
/// Resolving a path therefore produces this rather than a `URL`, and everything that attaches credentials takes only this. The unsafe case is then not merely avoided at each call site but unrepresentable, which is the difference between a rule and a habit.
struct SameOriginURL: Sendable {
    /// `logger` records every refusal under the `SameOriginURL` category.
    ///
    /// This type is a value rather than a facility, which normally means no logger at all. It has one because of what its failure means: a refusal here is the app declining to send the account's app password somewhere, and it is expressed as a `nil` that callers turn into "nothing opened". Without a line naming which rule fired, the one event most worth finding in a capture — a server having named an address off its own installation — is indistinguishable from a typo.
    private static let logger = Logger(for: SameOriginURL.self)

    /// `url` is the absolute location to request, known to be on the same origin as the server that named it.
    let url: URL

    /// `init?(path:relativeTo:)` resolves `path` against `serverAddress`, or returns `nil` if it does not stay on that server.
    ///
    /// `path` may be server-root-relative, as Nextcloud's own values are, or already absolute — some values arrive that way, and one on the right origin is no less safe for being spelled out. Anything that resolves elsewhere is refused, including the protocol-relative form (`//elsewhere.example/x.svg`), which reads like a path and is not one.
    ///
    /// **This is for a path the *server* named**, which is the whole of when to reach for it rather than for `init?(components:relativeTo:)`. Such a path already carries the instance's web root — the navigation endpoint answers `"/nextcloud/apps/files/"` on an instance installed in a subdirectory — so resolving it from the root is what puts it back where the server meant. A path the *app* knows carries no such prefix, and resolving one here moves it to the host's own root instead: a live page on the right server with nothing to do with the account, which is why that mistake reads as a working link. Build those with the other initializer.
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
    ///
    /// This exists because the other initializer is the wrong one for such a path, in a way that looks right and fails only on instances nobody tests against. A path the *server* named already carries the instance's web root: the navigation endpoint answers `"/nextcloud/apps/files/"` on an instance installed in a subdirectory, so resolving it from the root is correct. A path the app knows carries no such prefix, and resolving `"/settings/user"` from the root against `https://example.com/nextcloud` produces `https://example.com/settings/user` — a live page on that host with nothing to do with the account, which is why the mistake reads as a working link rather than as a failure.
    /// Taking components rather than a string is what makes the safe form the only form available. A caller holding a `"/settings/user"` literal has already made the decision this initializer exists to take away from them, and no amount of documentation on a `String` parameter prevents the next one from writing the same literal.
    /// Each component is appended with `appending(component:)` rather than `appending(path:)`, and the difference was measured rather than assumed: the two are identical for a component containing a space or a percent sign, and differ for one containing a slash, which `appending(path:)` passes through as a separator — so `"a/b"` becomes two segments there and one escaped segment here. A collective addressed by its name rather than its slug is the case where that reaches real data, the name being whatever somebody typed. An empty array, or any empty component, is refused: both mean a caller has built a path out of something it did not have, and the address that would result — the server's own root, or a path with a doubled separator — is a real page that would open and look like an answer.
    /// Three shapes are refused rather than built. An empty array, and any empty component, both mean a caller has assembled a path out of something it did not have, and what would result — the server's own root, or a path with a doubled separator — is a real page that opens and looks like an answer.
    /// A `.` or `..` component is the third, and that one is not tidiness: `appending(component:)` escapes a slash but passes a dot segment straight through, so two `..` in a row climb out of the instance's web root. Appending `["apps", "..", "..", "settings"]` to `https://example.com/nextcloud` yields an address a server resolves as `https://example.com/settings` — precisely the escape this initializer exists to prevent. Measured rather than assumed, and pinned by a test.
    /// It stays on the same origin, so the type's own promise is not broken by it. It matters because the components reaching here are frequently the *server's* values — a page's `filePath` split on `/`, a collective's name — so without this a server could name a path outside its own installation and be handed the account's app password for it.
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
    ///
    /// A port left out is the scheme's own, so `https://cloud.example.com` and `https://cloud.example.com:443` are one origin written two ways. Hosts compare case-insensitively, as DNS does.
    private static func isSameOrigin(_ url: URL, as other: URL) -> Bool {
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
