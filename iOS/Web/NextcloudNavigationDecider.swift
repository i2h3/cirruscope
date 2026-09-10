// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
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
    /// The address a silent retry is outstanding for and the moment it went out, or `nil` while none is.
    ///
    /// This is the retry budget, and both halves of it are load-bearing. The address is what keeps the budget from being spent by an unrelated page: a stale value can only ever be consumed by a second expiry on the very page that was retried. The moment is what keeps it from being spent at all once the retry can no longer be in flight, which is the case a retry that is never answered would otherwise leave open forever — the address in `redirect_url` is by construction the page the user was on and will most likely return to, so "never released" and "released on the wrong occasion" are the same defect here.
    /// A clock is the backstop rather than the mechanism. The ordinary release is `decidePolicy(for:)`'s response half, which fires the moment the server answers the retry at all; only a retry that gets no answer relies on the window below.
    ///
    private var outstandingRetry: (target: URL, issuedAt: ContinuousClock.Instant)?

    ///
    /// How long a retry may go unanswered before it is presumed lost rather than still outstanding.
    ///
    /// A sign-in form that is the server refusing the app password arrives as the redirected response to the retry, so it is one round trip behind it — well inside this. Anything still unanswered a minute later has failed, and `URLRequest`'s own default timeout says the same, so treating the budget as spent past that point could only ever sign out a user whose credentials are fine.
    ///
    private static let retryWindow = Duration.seconds(60)

    ///
    /// Records this decider's activity under the `NextcloudNavigationDecider` category.
    ///
    private let logger = Logger(for: NextcloudNavigationDecider.self)

    func decidePolicy(for action: WebPage.NavigationAction, preferences _: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        logger.debug("Deciding policy for a navigation action to \(action.request.url?.absoluteString ?? "no URL")")

        // Only the main frame. Nextcloud Office and similar editors load their own interface in a sub-frame, and a
        // sign-in form appearing inside one of those is not the session having lapsed on the page the user is looking
        // at. macOS draws the line in the same place, and for the same reason.
        guard action.target?.isMainFrame == true else {
            logger.debug("Navigation action does not target the main frame; returning .allow")
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

        guard NextcloudLoginPage.matches(url, on: account.server) else {
            logger.debug("Navigation action is not the connected server's sign-in form; returning .allow")
            return .allow
        }

        // The server names the page the redirected request had been for; where it names none that survives being
        // checked against the connected server, the server's own root is somewhere to land that always exists.
        let target = NextcloudLoginPage.redirectTarget(of: url, on: account.server) ?? account.server

        guard hasOutstandingRetry(for: target) == false else {
            logger.notice("Re-requesting \(target.absoluteString) with the stored app password already landed back on the sign-in form; the app password is no longer accepted, so requiring a new sign-in and returning .cancel")
            outstandingRetry = nil
            store.requireSignIn()

            return .cancel
        }

        outstandingRetry = (target, ContinuousClock.now)
        logger.notice("Navigation action targets the connected server's sign-in form; re-requesting \(target.absoluteString) with the stored app password instead of showing it, and returning .cancel")
        page?.load(account.authenticatedRequest(for: target))

        return .cancel
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        logger.debug("Deciding policy for a navigation response from \(response.response.url?.absoluteString ?? "no URL")")

        // Nothing here decides anything about the response itself; it is where a retry is learned to have been
        // answered. That cannot be read off the page's navigation events instead: cancelling the sign-in redirect
        // fails it provisionally, and `WebPage.navigations` reports a failure by throwing, which ends the sequence —
        // so the one signal that arrives reliably after an interception is this one.
        // Matched by address rather than taken as any response at all, so that a sub-frame of the document being
        // navigated away from cannot answer for the retry. A retry whose own chain ends somewhere else is left to
        // the window instead, which is the honest outcome: it is no longer a retry of what was asked for.
        if let outstandingRetry, response.response.url == outstandingRetry.target {
            logger.debug("The response answers the outstanding silent retry; retiring it")
            self.outstandingRetry = nil
        }

        logger.debug("Returning .allow")

        return .allow
    }

    ///
    /// Whether a silent retry of `target` is still outstanding, which is what makes a sign-in form reached again a rejected app password rather than a second expired cookie.
    ///
    private func hasOutstandingRetry(for target: URL) -> Bool {
        guard let outstandingRetry else {
            return false
        }

        guard outstandingRetry.target == target else {
            return false
        }

        return ContinuousClock.now - outstandingRetry.issuedAt < Self.retryWindow
    }
}
