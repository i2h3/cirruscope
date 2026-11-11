// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftUI
import WebKit

/// Decides what `NextcloudView`'s web view is allowed to navigate to: a navigation to the connected server's sign-in form is cancelled, and the page behind it re-requested with the stored app password.
@MainActor
final class NextcloudNavigationDecider: WebPage.NavigationDeciding {
    /// The page whose navigations are being decided, which is also what a cancelled sign-in redirect is re-requested through.
    ///
    /// Weak, and necessarily so: the page is built around this object and holds it for as long as it lives, so a strong reference back would close that loop and neither would ever be released.
    weak var page: WebPage?

    /// The app state the connected account is read from, or `nil` until `NextcloudView` has one to give.
    var store: Store?

    /// How an address off the connected server is handed to the browser, or `nil` until `NextcloudView` has one to give.
    ///
    /// SwiftUI's own action, taken from the view's environment for the same reason the store is taken from there: it is not available at the moment this object is built. Until it arrives, an outward link is left to the web view rather than swallowed, which is the milder of the two ways to be wrong about it.
    var openURL: OpenURLAction?

    /// The bookkeeping of the silent retries made while a lapsed browser session is being worked through, which answers every sign-in redirect, every check of the app password and every navigation response with the step to take next.
    ///
    /// It never answers a sign-out on its own inference, only once the server has refused the app password with HTTP 401 and that verdict has been reported back to it.
    /// Shared with macOS rather than reimplemented here, the bookkeeping being the subtle half of this whole decision and the half both apps previously got wrong in different ways.
    private var retryBudget = SilentRetryBudget()

    /// Records this decider's activity under the `NextcloudNavigationDecider` category.
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
        // Only the user activating a link to the route is that instruction. Nextcloud's session heartbeat with
        // `auto_logout` navigates here by script, which is the browser session timing itself out rather than the user
        // leaving, so it is cancelled and the account kept; `SignOutRequest` says why, and macOS reads it the same way.
        if route == .signOut {
            guard SignOutRequest.of(action.navigationType) == .explicit else {
                logger.notice("Navigation action targets the connected server's sign-out link but was not started by activating a link (type \(action.navigationType.rawValue, privacy: .public)); keeping the account and returning .cancel")
                return .cancel
            }

            logger.notice("Navigation action targets the connected server's sign-out link; signing out of the app as well and returning .cancel")
            store.logout()

            return .cancel
        }

        // The server names the page the redirected request had been for; where it names none that survives being
        // checked against the connected server, the server's own root is somewhere to land that always exists.
        let target = NextcloudSessionRoute.redirectTarget(of: url, on: account.server) ?? account.server

        // Whatever is done about it, the form itself is never shown: signing in happens natively, so the navigation
        // is cancelled in every case, and the budget only decides what happens instead of it.
        let step = retryBudget.signInFormReached(redirectingTo: target)
        logger.notice("Navigation action targets the connected server's sign-in form, which would return to \(target.absoluteString); acting on the silent retry's next step instead of showing it, and returning .cancel")
        perform(step, for: account)

        return .cancel
    }

    /// Carries out `step` on behalf of `account`, which is the one place a silent retry's step turns into something the page or the store does.
    private func perform(_ step: SilentRetryStep, for account: ServerAccount) {
        switch step {
            case let .retry(target):
                logger.notice("Stopping the stale page and re-requesting \(target.absoluteString) with the stored app password")
                page?.stopLoading()
                page?.load(account.authenticatedRequest(for: target))

            case let .confirmAppPassword(target):
                logger.notice("Asking the server whether it still accepts the stored app password before acting on the sign-in redirect for \(target.absoluteString)")

                let pageAtCheck = page?.url

                Task { [weak self] in
                    let verdict = await ServerConnection.verifyAppPassword(at: account.server, as: account.credentials)
                    self?.appPasswordCheckFinished(verdict, for: target, account: account, pageAtCheck: pageAtCheck)
                }

            case .wait:
                logger.debug("Nothing to do beyond cancelling, the silent retry being under way, on hold, or not concerned")

            case let .hold(target, duration):
                logger.notice("Pausing silent retries of \(target.absoluteString) for \(duration.components.seconds, privacy: .public) s while keeping the account signed in")

            case .signOut:
                logger.notice("The server refused the stored app password with HTTP 401; requiring a new sign-in")
                store?.requireSignIn()
        }
    }

    /// Hands the server's `verdict` on the app password, asked for on behalf of `target`, back to the budget and carries out whatever it answers.
    private func appPasswordCheckFinished(_ verdict: AppPasswordVerdict, for target: URL, account: ServerAccount, pageAtCheck: URL?) {
        guard store?.account == account else {
            logger.notice("The account changed while the server was being asked about its app password; discarding the answer and starting the silent retry over")
            retryBudget.reset()

            return
        }

        guard verdict == .rejected || page?.url == pageAtCheck else {
            logger.notice("The page moved on while the server was being asked about the app password; discarding the answer, which is \(String(describing: verdict), privacy: .public), and starting the silent retry over")
            retryBudget.reset()

            return
        }

        logger.debug("The server's answer about the stored app password for \(target.absoluteString) is \(String(describing: verdict), privacy: .public)")
        perform(retryBudget.appPasswordChecked(verdict, for: target), for: account)
    }

    /// Whether the system took `url` off this web view's hands, having been offered it because it is not the connected server's.
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

        guard let account = store?.account else {
            logger.debug("No account is configured; returning .allow")
            return .allow
        }

        // Nothing here decides anything about the response itself; it is where a retry is learned to have been
        // answered, or refused with the HTTP 401 a page request carrying a refused app password receives. That cannot
        // be read off the page's navigation events instead: cancelling the sign-in redirect fails it provisionally,
        // and `WebPage.navigations` reports a failure by throwing, which ends the sequence — so the one signal that
        // arrives reliably after an interception is this one.
        // Unlike `WKNavigationResponse` on macOS, `WebPage.NavigationResponse` does not say whether it answers the
        // main frame. What keeps a sub-frame's response from being taken for the retried page's is that the budget
        // acts only on a response from the very address it is retrying or holding.
        let statusCode = (response.response as? HTTPURLResponse)?.statusCode
        perform(retryBudget.responseArrived(from: response.response.url, statusCode: statusCode), for: account)

        logger.debug("Returning .allow")

        return .allow
    }
}
