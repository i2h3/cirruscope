// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NextcloudSessionRoute` is one of the two addresses on a Nextcloud server that change who the embedded web view is signed in as, recognized from a URL the web view is about to navigate to.
enum NextcloudSessionRoute {
    /// `signIn` is the sign-in form, `core.login.showLoginForm`, which a server redirects an unauthenticated request for a page to.
    case signIn

    /// `signOut` is the sign-out link, `core.login.logout`, which Nextcloud's own account menu offers.
    case signOut

    /// `component` is the single path component, immediately below the server's web root, that this route lives at.
    private var component: String {
        switch self {
            case .signIn:
                "login"

            case .signOut:
                "logout"
        }
    }

    /// `redirectParameter` is the query parameter the sign-in form carries the originally requested address in.
    private static let redirectParameter = "redirect_url"

    /// `matching(_:on:)` is the session route `url` addresses on the server at `serverAddress`, or `nil` when it addresses neither.
    static func matching(_ url: URL, on serverAddress: URL) -> NextcloudSessionRoute? {
        guard let components = ServerAppPath.relativeComponents(of: url, on: serverAddress) else {
            return nil
        }

        guard components.count == 1 else {
            return nil
        }

        return [.signIn, .signOut].first { $0.component == components[0] }
    }

    /// `redirectTarget(of:on:)` is the address the sign-in form at `url` says the redirected request had been for, or `nil` where it names none, names one off the server, or names a session route again.
    static func redirectTarget(of url: URL, on serverAddress: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard let value = components.queryItems?.first(where: { $0.name == Self.redirectParameter })?.value else {
            return nil
        }

        guard let target = SameOriginURL(path: value, relativeTo: serverAddress) else {
            return nil
        }

        guard Self.matching(target.url, on: serverAddress) == nil else {
            return nil
        }

        return target.url
    }
}
