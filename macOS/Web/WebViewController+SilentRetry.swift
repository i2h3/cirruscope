// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

///
/// `WebViewController+SilentRetry` carries out what `retryBudget` answers while this window works through a lapsed browser session: it re-requests a page with the stored app password, asks the server whether it still accepts that password, holds, or signs out.
///
/// `WebViewController+WKNavigationDelegate` reports what the web view's navigations show and hands the answer here, and so does the check of the app password once the server has replied, so every step the budget can answer is acted on in one place.
/// Signing out is only ever the server's decision: the web view on its own can only suspect that the app password was refused, `ServerConnection.verifyAppPassword(at:as:)` asks, and `retryBudget` answers `SilentRetryStep.signOut` only for its HTTP 401.
/// A credential the Keychain will not hand over, a server that cannot be reached and a reply arriving after this window closed or the account changed are all answered with anything but a sign-out.
///
extension WebViewController {
    ///
    /// `performSilentRetryStep(_:on:)` does what `step` asks of this window, `serverAddress` being the connected server the check of the app password is made against.
    ///
    /// A hold in a window that has shown a page does nothing but log: there is nothing for the user to do while it lasts, and the stale page's next redirect to the sign-in form after it ends starts the recovery again by itself.
    /// A hold reached before any page was shown has no stale page to do that, so it switches the window to its failure state, whose retry button starts over.
    /// The caller has to have handed back any navigation decision it was asked for before calling this, because a retry starts a load of its own.
    ///
    func performSilentRetryStep(_ step: SilentRetryStep, on serverAddress: URL) {
        switch step {
            case let .retry(target):
                logger.notice("Re-requesting \(target.absoluteString) with the stored app password (WebViewController \(self.logID))")
                webView.stopLoading()
                webView.load(authenticatedRequest(for: target))

            case let .confirmAppPassword(target):
                confirmAppPassword(returningTo: target, on: serverAddress)

            case .wait:
                logger.debug("Nothing to do about the browser session right now (WebViewController \(self.logID))")

            case let .hold(target, duration):
                logger.notice("Holding silent retries of \(target.absoluteString) for \(duration.components.seconds, privacy: .public) s while keeping the account (WebViewController \(self.logID))")

                guard hasRevealedAfterInitialLoad else {
                    logger.notice("No page has been shown in this window yet, so nothing would start the recovery again; offering the retry button instead (WebViewController \(self.logID))")
                    showFailureState(retrying: target)
                    return
                }

            case .signOut:
                logger.notice("The server rejected the stored app password; requiring sign-in (WebViewController \(self.logID))")
                (NSApp.delegate as? AppDelegate)?.requireSignIn()
        }
    }

    ///
    /// `confirmAppPassword(returningTo:on:)` asks the server at `serverAddress` whether it still accepts the stored app password, on behalf of `target`, the page to return to.
    ///
    /// Credentials the Keychain does not hand over are reported to `retryBudget` as `AppPasswordVerdict.undetermined`, because a Keychain that refuses a read says nothing about what the server would answer and must never sign anybody out.
    /// The check runs in a `Task` that inherits this controller's main actor, so only the `Sendable` address and credentials cross into `ServerConnection.verifyAppPassword(at:as:)` and only its `Sendable` verdict crosses back; the controller is held weakly, so a window that closes meanwhile is not kept alive for an answer nobody needs.
    ///
    private func confirmAppPassword(returningTo target: URL, on serverAddress: URL) {
        guard let credentials = Keychain.credentials(for: serverAddress) else {
            logger.notice("No stored app password could be read to confirm with the server; treating the check as undetermined rather than signing out (WebViewController \(self.logID))")
            performSilentRetryStep(retryBudget.appPasswordChecked(.undetermined, for: target), on: serverAddress)
            return
        }

        logger.notice("Asking the server whether it still accepts the stored app password before returning to \(target.absoluteString) (WebViewController \(self.logID))")

        let pageAtCheck = webView.url

        Task { [weak self] in
            let verdict = await ServerConnection.verifyAppPassword(at: serverAddress, as: credentials)
            self?.appPasswordCheckFinished(verdict, for: target, on: serverAddress, as: credentials, pageAtCheck: pageAtCheck)
        }
    }

    ///
    /// `appPasswordCheckFinished(_:for:on:as:pageAtCheck:)` hands `verdict`, what the server said about `credentials` on behalf of `target`, to `retryBudget` and does what it answers, provided the answer still concerns anybody.
    ///
    /// A verdict arriving once this controller's view is no longer in a window is discarded, as is one arriving after the account it was asked for stopped being the one signed in at `serverAddress`.
    /// The second is what keeps several windows that suspected the same lapse to a single sign-out and a single alert: the first one to hear HTTP 401 signs out, and every later verdict finds the account gone, even in a window that was closed but is still alive.
    /// A verdict short of a refusal is also discarded once the web view shows another page than `pageAtCheck`, the one it showed when the check was asked for, so that a check answered late cannot pull the user back from a page they went on to.
    /// A refusal is acted on regardless, being the server's own answer about the credential.
    ///
    private func appPasswordCheckFinished(_ verdict: AppPasswordVerdict, for target: URL, on serverAddress: URL, as credentials: Credentials, pageAtCheck: URL?) {
        guard view.window != nil else {
            logger.notice("Discarding the app password check's verdict \(String(describing: verdict), privacy: .public) because this view is no longer in a window (WebViewController \(self.logID))")
            return
        }

        guard ServerConnection.isStillSignedIn(at: serverAddress, as: credentials) else {
            logger.notice("Discarding the app password check's verdict \(String(describing: verdict), privacy: .public) because the account it was asked for is no longer the one signed in (WebViewController \(self.logID))")
            retryBudget.reset()
            return
        }

        guard verdict == .rejected || webView.url == pageAtCheck else {
            logger.notice("Discarding the app password check's verdict \(String(describing: verdict), privacy: .public) because the page has moved on since it was asked for; the next lapse starts over (WebViewController \(self.logID))")
            retryBudget.reset()
            return
        }

        logger.notice("The app password check answered \(String(describing: verdict), privacy: .public) on the way back to \(target.absoluteString) (WebViewController \(self.logID))")
        performSilentRetryStep(retryBudget.appPasswordChecked(verdict, for: target), on: serverAddress)
    }
}
