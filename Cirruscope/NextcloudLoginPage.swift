// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NextcloudLoginPage` recognizes the sign-in page a Nextcloud server sends a request to once the browser session behind it has lapsed, and reads back the page that request had been for.
///
/// A server answers an unauthenticated request for an HTML page with a redirect to its sign-in form, naming the address originally asked for in a `redirect_url` query parameter. That happens on the session cookie's own schedule rather than the app's — it expires while the app is away, and the first navigation after the app comes back is redirected — and it says nothing about whether the app password the app itself holds is still good. The embedded web view therefore intercepts the redirect and re-requests the page behind it with that password attached instead of letting a sign-in form appear that the user could not usefully complete, and the part of that decision which is pure address arithmetic lives here.
/// Both halves are deliberately narrow. The form is matched at the server's own web root and nowhere else, so neither a file a user happened to name "login" nor a second installation on the same host is mistaken for it, and neither are the `/login/…` pages that are not this redirect — password confirmation, two-factor challenges, and the Login Flow v2 grant screens, none of which a silent retry would help and all of which the user is meant to see. The redirect target is resolved through `SameOriginURL`, because the app reads that query parameter straight off the address bar, long before the server's own handling of it would run, and it is therefore no more trustworthy than any other string a page can put in a link.
enum NextcloudLoginPage {
    /// `path` is where the sign-in form lives below a server's web root, which is the only place it is recognized.
    private static let path = "/login"

    /// `frontControllerSegment` is the `/index.php` an instance without URL rewriting puts in front of every one of its routes, and which is absent from exactly the same routes on an instance that has it.
    ///
    /// Whether it appears is per-instance configuration rather than anything a client chooses, so both spellings of the sign-in form have to be recognized.
    private static let frontControllerSegment = "/index.php"

    /// `redirectParameter` is the query parameter the sign-in form carries the originally requested address in.
    private static let redirectParameter = "redirect_url"

    /// `matches(_:on:)` reports whether `url` is the sign-in form of the server at `serverAddress`.
    ///
    /// The origin is compared through `SameOriginURL` rather than by host alone, so a plain-HTTP or differently-ported service on the same machine is not taken for the connected server. The path is then compared after the server's web root, so only the instance's own sign-in form matches and nothing that merely ends in the same word does.
    static func matches(_ url: URL, on serverAddress: URL) -> Bool {
        guard SameOriginURL(path: url.absoluteString, relativeTo: serverAddress) != nil else {
            return false
        }

        var webRoot = serverAddress.path(percentEncoded: true)
        var path = url.path(percentEncoded: true)

        // A trailing slash is not part of a web root. The canonical address the app stores never carries one, but an
        // address that reached the app another way would otherwise shift every comparison below by one character and
        // match nothing at all.
        if webRoot.hasSuffix("/") {
            webRoot.removeLast()
        }

        guard path.hasPrefix(webRoot) else {
            return false
        }

        path.removeFirst(webRoot.count)

        if path.hasPrefix(Self.frontControllerSegment) {
            path.removeFirst(Self.frontControllerSegment.count)
        }

        if path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }

        return path == Self.path
    }

    /// `redirectTarget(of:on:)` is the address the sign-in form at `url` says the redirected request had been for, or `nil` where it names none, names one off the server, or names the sign-in form again.
    ///
    /// A caller with nothing to reload from this still has somewhere to go — the server's own root — so the absence is reported rather than guessed at. Refusing a target that is itself the sign-in form matters for the same reason: reloading it would be a redirect intercepted into a reload of itself.
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

        guard Self.matches(target.url, on: serverAddress) == false else {
            return nil
        }

        return target.url
    }
}
