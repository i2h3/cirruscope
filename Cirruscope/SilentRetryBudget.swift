// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SilentRetryBudget` is the one silent retry an embedded web view is allowed per episode of a lapsed browser session, and the record of whether it has been spent.
///
/// It exists because the sign-in form a Nextcloud server redirects to means two different things and the app has to tell them apart. Nearly always it means the browser session's cookie expired while the app was away, which says nothing about the app password the app itself holds: re-requesting the page with that password signs the web view straight back in. Occasionally it means the app password is no longer accepted, and then the same retry comes back to the same form, and the honest answer is to sign the account out. One retry distinguishes the two.
/// Both halves of what is remembered are load-bearing, and both are answers to ways of getting this wrong that cost a user their session. The address keeps an unrelated page from spending the budget, so a second expiry somewhere else still gets its own retry. The moment keeps a retry that is never answered from spending it forever — the address being retried is by construction the page the user was on and will most likely return to, so a budget that is never released and one that is released on the wrong occasion are the same defect.
/// A clock is the backstop rather than the mechanism. The ordinary release is `releaseIfAnswered(by:)`, called the moment the server answers the retry at all; only a retry that gets no answer relies on the window.
struct SilentRetryBudget {
    /// `outstanding` is the address a retry is in flight for and the moment it went out, or `nil` while none is.
    private var outstanding: (target: URL, issuedAt: ContinuousClock.Instant)?

    /// `window` is how long a retry may go unanswered before it is presumed lost rather than still outstanding.
    ///
    /// A sign-in form that is the server refusing the app password arrives as the redirected response to the retry, so it is one round trip behind it and well inside any sane value here. Anything still unanswered a minute later has failed, and `URLRequest`'s own default timeout says the same, so treating the budget as spent past that point could only ever sign out a user whose credentials are fine.
    private let window: Duration

    /// `init(window:)` builds a budget that presumes an unanswered retry lost after `window`.
    ///
    /// The default is the one both apps use; the parameter exists so a test can state the passage of time instead of waiting for it.
    init(window: Duration = .seconds(60)) {
        self.window = window
    }

    /// `isSpent(on:at:)` reports whether the retry of `target` is the one already made and still outstanding at `instant`, which is what makes a sign-in form reached again a rejected app password rather than a second expired cookie.
    func isSpent(on target: URL, at instant: ContinuousClock.Instant = .now) -> Bool {
        guard let outstanding else {
            return false
        }

        guard outstanding.target == target else {
            return false
        }

        return instant - outstanding.issuedAt < window
    }

    /// `spend(on:at:)` records that `target` has just been re-requested with the stored app password.
    mutating func spend(on target: URL, at instant: ContinuousClock.Instant = .now) {
        outstanding = (target, instant)
    }

    /// `releaseIfAnswered(by:)` retires the outstanding retry when `url` is the address it was made for.
    ///
    /// Matched by address rather than taken as any answer at all, so that a sub-frame of the document being navigated away from cannot answer for the retry. A retry whose own chain ends somewhere else is left to the window instead, which is the honest outcome: it is no longer a retry of what was asked for.
    mutating func releaseIfAnswered(by url: URL?) {
        guard let outstanding else {
            return
        }

        guard url == outstanding.target else {
            return
        }

        self.outstanding = nil
    }

    /// `release()` retires whatever retry is outstanding, whether it was answered or not.
    mutating func release() {
        outstanding = nil
    }
}
