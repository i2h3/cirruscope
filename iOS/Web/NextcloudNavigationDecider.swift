// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftUI
import WebKit

///
/// Decides what `NextcloudView`'s web view is allowed to navigate to, which for the moment is one decision: a navigation to the connected server's sign-in form is cancelled, and the page behind it re-requested with the stored app password.
///
/// It exists because of what a user sees without it. The web view's browser session is a cookie the server issues and expires on its own schedule, independently of the app password the app itself holds, so an app left alone for a few hours comes back to a first navigation that the server redirects to its sign-in form — and that form is a dead end here, since signing in happens natively through Login Flow v2 and not in the page. Re-requesting the redirected-from page with the app password attached signs the web view back in exactly the way the initial load does, and the user sees the page they left. macOS has done this since its own web view was written, in `WebViewController+WKNavigationDelegate`.
/// One retry is allowed per episode. A retry that itself comes back to the sign-in form means the app password is no longer accepted rather than that a cookie lapsed, and that is a genuine sign-out — `Store.requireSignIn()` — instead of a loop.
/// It is a class because `WebPage` takes its decider by value at initialization and holds it from then on, while the two things this needs — the page to reload through and the store to read the account from — only exist afterwards. That is the same shape, and the same reason, as `AppNavigationBridge` and `NotificationsPanelBridge`.
///
@MainActor
final class NextcloudNavigationDecider: WebPage.NavigationDeciding {
    ///
    /// The page whose navigations are being decided, which is also what a cancelled sign-in redirect is re-requested through.
    ///
    /// Weak, and necessarily so: the page is built around this object and holds it for as long as it lives, so a strong reference back would close that loop and neither would ever be released.
    ///
    weak var page: WebPage?

    ///
    /// The app state the connected account is read from, or `nil` until `NextcloudView` has one to give.
    ///
    /// Assigned from the view's body rather than through an initializer: this object is built in `NextcloudView.init()`, which runs before SwiftUI has installed the view's environment and therefore before there is a store to read. Until it arrives, every navigation is allowed — there is no account to sign a retry with, so there is nothing this could usefully decide.
    ///
    var store: Store?

    ///
    /// How an address off the connected server is handed to the browser, or `nil` until `NextcloudView` has one to give.
    ///
    /// SwiftUI's own action, taken from the view's environment for the same reason the store is taken from there: it is not available at the moment this object is built. Until it arrives, an outward link is left to the web view rather than swallowed, which is the milder of the two ways to be wrong about it.
    ///
    var openURL: OpenURLAction?

    ///
    /// The one silent retry allowed while a lapsed browser session is being worked through, and whether it has been spent.
    ///
    /// Shared with macOS rather than reimplemented here, the bookkeeping being the subtle half of this whole decision and the half both apps previously got wrong in different ways.
    ///
    private var retryBudget = SilentRetryBudget()

    ///
    /// Records this decider's activity under the `NextcloudNavigationDecider` category.
    ///
    private let logger = Logger(for: NextcloudNavigationDecider.self)

    func decidePolicy(for action: WebPage.NavigationAction, preferences _: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        logger.debug("Deciding policy for a navigation action to \(action.request.url?.absoluteString ?? "no URL")")

        // A sub-frame is left alone. Nextcloud Office and similar editors load their own interface in one, hosted on
        // a different domain than the server itself, and neither a sign-in form nor an outside address appearing
        // inside such a frame is the user leaving the page — it is the page. macOS draws the line in the same place.
        // A navigation carrying no target frame at all is not a sub-frame but a request for a new window, which is
        // what `target="_blank"` produces and what most of Nextcloud's outward links are. There is no second window
        // to put it in here, so it is decided like any other navigation of the frame the user is looking at; macOS
        // sends the same case to a `WKUIDelegate` that opens a window instead.
        if let target = action.target, target.isMainFrame == false {
            logger.debug("Navigation action targets a sub-frame; returning .allow")
            return .allow
        }

        guard let url = action.request.url else {
            logger.debug("Navigation action has no URL; returning .allow")
            return .allow
        }

        guard let store else {
            logger.debug("No store has been handed over yet; returning .allow")
            return .allow
        }

        guard let account = store.account else {
            logger.debug("No account is configured; returning .allow")
            return .allow
        }

        guard let route = NextcloudSessionRoute.matching(url, on: account.server) else {
            guard WebViewDestination.of(url, connectedTo: account.server) == .system else {
                logger.debug("Navigation action addresses neither of the connected server's session routes and is the web view's own to display; returning .allow")
                return .allow
            }

            guard await systemOpened(url) else {
                logger.notice("Navigation action targets \(url.absoluteString), which is off the connected server, but the system did not open it; leaving it to the web view and returning .allow")
                return .allow
            }

            logger.notice("Navigation action targets \(url.absoluteString), which is off the connected server; the system opened it, so returning .cancel")

            return .cancel
        }

        // Nextcloud's own "Log out" is an unambiguous instruction, so it is widened rather than reversed: the
        // navigation is cancelled and the account signed out of the app too. Cancelling means the server never
        // processes the request, which is why the sign-out has to revoke the app password itself — `Store.logout()`
        // does, and without it the browser session would end while a working credential stayed on the account's
        // device list. macOS reads the same link the same way.
        guard route != .signOut else {
            logger.notice("Navigation action targets the connected server's sign-out link; signing out of the app as well and returning .cancel")
            store.logout()

            return .cancel
        }

        // The server names the page the redirected request had been for; where it names none that survives being
        // checked against the connected server, the server's own root is somewhere to land that always exists.
        let target = NextcloudSessionRoute.redirectTarget(of: url, on: account.server) ?? account.server

        guard retryBudget.isSpent(on: target) == false else {
            logger.notice("Re-requesting \(target.absoluteString) with the stored app password already landed back on the sign-in form; the app password is no longer accepted, so requiring a new sign-in and returning .cancel")
            retryBudget.release()
            store.requireSignIn()

            return .cancel
        }

        retryBudget.spend(on: target)
        logger.notice("Navigation action targets the connected server's sign-in form; re-requesting \(target.absoluteString) with the stored app password instead of showing it, and returning .cancel")
        page?.load(account.authenticatedRequest(for: target))

        return .cancel
    }

    ///
    /// Whether the system took `url` off this web view's hands, having been offered it because it is not the connected server's.
    ///
    /// `WebViewDestination` decides what is worth offering; this is the iOS half of acting on that, and the offer is made through SwiftUI's own `openURL` rather than `UIApplication`, so the app never has to ask which schemes the device can open. That question has an official answer only for schemes an app declares in advance, and it does not need asking: opening reports whether it worked, and everything the system declines is handed straight back to WebKit, which then fails the navigation the way it would have anyway.
    /// The completion is awaited rather than ignored because the policy this informs cannot be given twice. Cancelling a navigation the system then refused to open would leave the user tapping a link that does nothing at all.
    ///
    private func systemOpened(_ url: URL) async -> Bool {
        guard let openURL else {
            logger.error("Navigation action to \(url.absoluteString) leaves the connected server, but no way to open it has been handed over; leaving it to the web view")
            return false
        }

        return await withCheckedContinuation { continuation in
            openURL(url) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        logger.debug("Deciding policy for a navigation response from \(response.response.url?.absoluteString ?? "no URL")")

        // Nothing here decides anything about the response itself; it is where a retry is learned to have been
        // answered. That cannot be read off the page's navigation events instead: cancelling the sign-in redirect
        // fails it provisionally, and `WebPage.navigations` reports a failure by throwing, which ends the sequence —
        // so the one signal that arrives reliably after an interception is this one.
        retryBudget.releaseIfAnswered(by: response.response.url)

        logger.debug("Returning .allow")

        return .allow
    }
}
