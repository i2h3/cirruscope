// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NextcloudSessionRoute` is one of the two addresses on a Nextcloud server that change who the embedded web view is signed in as, recognized from a URL the web view is about to navigate to.
///
/// Both are intercepted rather than followed, and for opposite reasons. The sign-in form is somewhere the *server* sends the web view, on the session cookie's own schedule rather than the app's: the cookie lapses while the app is away, and the first navigation after it comes back is redirected — which says nothing about whether the app password the app itself holds is still good. The sign-out link is somewhere the *user* sends it, by using Nextcloud's own "Log out" item, and letting the page handle that alone would end the browser session while leaving the app signed in with a still-valid app password. So the first is reversed by re-requesting the page behind it with that password, and the second is widened into signing the account out of the app as well.
/// Recognition is deliberately narrow, because both interceptions cancel a navigation the user asked for and the sign-out one destroys a credential. A route is matched only as the instance's own, immediately below its web root: neither a file a user happened to name "login" nor a second installation on the same host is one, and neither are the `/login/…` pages that change nothing about who is signed in — password confirmation, two-factor challenges, and the Login Flow v2 grant screens, all of which the user is meant to see and complete.
/// The normalizing is `ServerAppPath`'s, so this and the app resolution the navigation bar titles itself from cannot come to different conclusions about which instance an address belongs to, nor about the `/index.php` segment an instance without URL rewriting serves everything under.
enum NextcloudSessionRoute {
    /// `signIn` is the sign-in form, `core.login.showLoginForm`, which a server redirects an unauthenticated request for a page to.
    case signIn

    /// `signOut` is the sign-out link, `core.login.logout`, which Nextcloud's own account menu offers.
    case signOut

    /// `component` is the single path component, immediately below the server's web root, that this route lives at.
    ///
    /// Compared exactly rather than case-insensitively, because a Nextcloud route is: an instance answers `/login` and 404s `/LOGIN`, so accepting the second could only ever match something that is not this route.
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
    ///
    /// The origin is proven and the path normalized by `ServerAppPath.relativeComponents(of:on:)`, so a plain-HTTP or differently-ported service on the same machine is not taken for the connected server, and an instance served under `/index.php/` or installed in a subdirectory is recognized as readily as one that is neither.
    /// Exactly one component, so only the route itself matches and nothing below it does. That is what keeps `/login/flow` and `/login/confirm` — pages the user is meant to complete — from being cancelled.
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
    ///
    /// A caller with nothing to reload from this still has somewhere to go — the server's own root — so the absence is reported rather than guessed at. Refusing a target that is itself a session route matters for the same reason: the sign-in form would be a redirect intercepted into a reload of itself, and the sign-out link would turn a lapsed cookie into a sign-out the user never asked for.
    /// The value is resolved through `SameOriginURL` because the app reads it straight off the address bar, long before the server's own handling of it would run, and it is therefore no more trustworthy than any other string a page can put in a link — while what it decides is where an app password is about to be sent.
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
