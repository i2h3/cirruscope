// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SilentRetryBudget` decides what an embedded web view does while it works through a lapsed browser session, answering each event with the `SilentRetryStep` to take next.
struct SilentRetryBudget {
    /// `episodeTarget` is the page the current episode is retrying, or `nil` while no retry is outstanding.
    private var episodeTarget: URL?

    /// `attempts` is how many times `episodeTarget` has been re-requested in the current episode.
    private var attempts = 0

    /// `lastRetryAt` is when `episodeTarget` was last re-requested, which is what a redirect to the sign-in form is measured against to tell a suspicious one from a fresh expiry.
    private var lastRetryAt: ContinuousClock.Instant?

    /// `confirmingSince` is when the check of the app password now in flight was asked for, or `nil` while none is.
    private var confirmingSince: ContinuousClock.Instant?

    /// `held` is the page whose silent retries are paused and the moment that pause ends, or `nil` while none is.
    private var held: (target: URL, until: ContinuousClock.Instant)?

    /// `consecutiveHolds` is how many holds have been imposed since a retry was last answered, from which the next hold's length doubles.
    private var consecutiveHolds = 0

    /// `window` is how long after a retry a redirect to the sign-in form for the same page counts as suspicious rather than as a new expiry.
    let window: Duration

    /// `confirmationTimeout` is how long a check of the app password may stay unanswered before it is presumed lost, and a later redirect or HTTP 401 may ask again.
    let confirmationTimeout: Duration

    /// `maximumAttempts` is how many times one episode may re-request its page before it holds instead.
    let maximumAttempts: Int

    /// `firstHold` is how long the first hold since a retry was last answered lasts.
    let firstHold: Duration

    /// `longestHold` is the length no hold exceeds, however many came before it.
    let longestHold: Duration

    /// `init(window:confirmationTimeout:maximumAttempts:firstHold:longestHold:)` builds a budget with the given limits.
    ///
    /// The defaults are the ones both apps use; the parameters exist so a test can state them rather than depend on them.
    init(window: Duration = .seconds(60), confirmationTimeout: Duration = .seconds(120), maximumAttempts: Int = 3, firstHold: Duration = .seconds(60), longestHold: Duration = .seconds(30 * 60)) {
        self.window = window
        self.confirmationTimeout = confirmationTimeout
        self.maximumAttempts = maximumAttempts
        self.firstHold = firstHold
        self.longestHold = longestHold
    }

    /// `signInFormReached(redirectingTo:at:)` is what to do about a main-frame navigation to the server's sign-in form that would return to `target`.
    mutating func signInFormReached(redirectingTo target: URL, at instant: ContinuousClock.Instant = .now) -> SilentRetryStep {
        if let confirmingSince {
            guard instant - confirmingSince >= confirmationTimeout else {
                return .wait
            }

            self.confirmingSince = nil
        }

        if let held, held.target == target {
            guard instant >= held.until else {
                return .wait
            }

            self.held = nil
        }

        if episodeTarget == target, let lastRetryAt, instant - lastRetryAt < window {
            confirmingSince = instant
            return .confirmAppPassword(target)
        }

        episodeTarget = target
        attempts = 1
        lastRetryAt = instant

        return .retry(target)
    }

    /// `appPasswordChecked(_:for:at:)` is what to do once the server has been asked about the app password on behalf of `target` and `verdict` is what it said.
    mutating func appPasswordChecked(_ verdict: AppPasswordVerdict, for target: URL, at instant: ContinuousClock.Instant = .now) -> SilentRetryStep {
        confirmingSince = nil

        guard verdict != .rejected else {
            reset()
            return .signOut
        }

        guard episodeTarget == target else {
            return .wait
        }

        guard verdict == .accepted, attempts < maximumAttempts else {
            return hold(target, at: instant)
        }

        attempts += 1
        lastRetryAt = instant

        return .retry(target)
    }

    /// `responseArrived(from:statusCode:at:)` is what to do about a main-frame response from `url` that answered with `statusCode`.
    ///
    /// Only a response for the page being retried or held concerns this budget. An HTTP 401 for it is how a page request carrying a refused app password is answered, so it asks for a check unless one is already in flight and not yet presumed lost. Any other response means the server answered, which ends the episode, its hold and the hold's growth.
    mutating func responseArrived(from url: URL?, statusCode: Int?, at instant: ContinuousClock.Instant = .now) -> SilentRetryStep {
        guard let url else {
            return .wait
        }

        guard url == episodeTarget || url == held?.target else {
            return .wait
        }

        if statusCode == 401 {
            if let confirmingSince, instant - confirmingSince < confirmationTimeout {
                return .wait
            }

            confirmingSince = instant
            return .confirmAppPassword(url)
        }

        episodeTarget = nil
        attempts = 0
        lastRetryAt = nil
        held = nil
        consecutiveHolds = 0

        return .wait
    }

    /// `reset()` forgets everything, for a load the user asked for, which starts over, and for a check's answer that arrives once the account it was asked for is no longer the one signed in or the page it was asked for has moved on.
    mutating func reset() {
        episodeTarget = nil
        attempts = 0
        lastRetryAt = nil
        confirmingSince = nil
        held = nil
        consecutiveHolds = 0
    }

    /// `hold(_:at:)` ends the episode for `target` and pauses its silent retries, each hold since a retry was last answered lasting twice as long as the one before, up to `longestHold`.
    private mutating func hold(_ target: URL, at instant: ContinuousClock.Instant) -> SilentRetryStep {
        var duration = firstHold

        for _ in 0 ..< consecutiveHolds where duration < longestHold {
            duration *= 2
        }

        duration = min(duration, longestHold)
        consecutiveHolds += 1
        held = (target, instant.advanced(by: duration))
        episodeTarget = nil
        attempts = 0
        lastRetryAt = nil

        return .hold(target, for: duration)
    }
}
