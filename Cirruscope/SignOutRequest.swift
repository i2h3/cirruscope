// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WebKit

///
/// `SignOutRequest` is what a navigation to the connected server's sign-out route asks of the app, judged by how the navigation began.
///
/// Nextcloud's own "Log out" is a plain link, so the user choosing it is a navigation WebKit reports as `WKNavigationType.linkActivated`, and that is widened into signing the account out of the app and revoking its app password.
/// The page's own script can navigate to the same route as well: with `auto_logout` set, Nextcloud's session heartbeat assigns the sign-out address to `location.href` once no mouse or touch input arrived for the session's lifetime, which WebKit reports as `.other`.
/// That is the browser session timing itself out, not the user asking to leave, and an app holding an app password is not a browser on a shared computer, so it is cancelled and the account kept.
/// Letting it through instead would not protect anything either: the server's sign-out ends only the browser session a request with the app password started, and the app would sign that straight back in.
/// What this cannot tell apart is a script activating a link to the route, which WebKit reports as `.linkActivated` too; nothing in Nextcloud does that.
///
enum SignOutRequest: Equatable {
    /// `explicit` means the user activated a link to the sign-out route, so the account is to be signed out of the app and its app password revoked.
    case explicit

    /// `scripted` means the navigation began some other way, typically the page's own script, so it is to be cancelled and the account kept.
    case scripted

    ///
    /// `of(_:)` is what a navigation to the sign-out route of type `navigationType` asks of the app.
    ///
    /// Only link activation is explicit.
    /// A form submission, a reload, a step through the history, an app-initiated load and a script assigning the location are all `scripted`, as is any type a later SDK adds.
    ///
    static func of(_ navigationType: WKNavigationType) -> SignOutRequest {
        switch navigationType {
            case .linkActivated:
                .explicit

            case .formSubmitted, .backForward, .reload, .formResubmitted, .other:
                .scripted

            @unknown default:
                .scripted
        }
    }
}
