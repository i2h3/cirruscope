// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `SilentRetryBudgetTests` covers `SilentRetryBudget`, which decides what a web view does while it works through a lapsed browser session.
///
/// The suite exists because this decision has signed out users whose app password the server still accepted, on both platforms and more than once: on 2026-10-09 the stale page's own script navigating to the sign-in form was taken for the silent retry having been refused.
/// So the one property every case below serves is that only the server's own refusal of the app password signs out, never a redirect, a response or the passage of time, and the property cases check it over fixed, generated sequences of events rather than only over the ones somebody thought of.
/// The other cases pin what is done instead, a retry, a check, a wait or a hold, and that the work stays bounded, so a page the server keeps refusing to restore is held rather than retried forever.
/// Every instant is passed in rather than read, so the window, the confirmation timeout and the holds are tested without waiting for any of them.
///
struct SilentRetryBudgetTests {
    ///
    /// `target` is the page a retry is made for in most cases below.
    ///
    private static let target = URL(string: "https://cloud.example.com/apps/files/")!

    ///
    /// `otherTarget` is a second page, for the cases about one page's episode, check or hold and another page.
    ///
    private static let otherTarget = URL(string: "https://cloud.example.com/apps/spreed/")!

    ///
    /// `seeds` are the seeds the property cases draw their sequences of events from, one sequence each.
    ///
    /// They are fixed, so every run covers the same sequences and a failure names the seed that reproduces it.
    ///
    private static let seeds: [UInt64] = Array(0 ..< 200)

    ///
    /// `eventsPerSequence` is how many events each of those sequences holds.
    ///
    private static let eventsPerSequence = 60

    // MARK: - Redirects to the Sign-In Form

    @Test
    func `A first redirect to the sign-in form retries its page`() {
        var budget = SilentRetryBudget()

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: ContinuousClock.now) == .retry(Self.target))
    }

    @Test
    func `Another redirect for the same page within the window asks the server rather than signing out`() {
        // This is the redirect that used to sign out: it may be the stale page's own script superseding the retry,
        // which says nothing about the app password.
        var budget = SilentRetryBudget(window: .seconds(60))
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(59)) == .confirmAppPassword(Self.target))
    }

    @Test
    func `A redirect for the same page after the window is a fresh expiry and starts its attempts over`() {
        // With two attempts, an accepted check after the second retry would hold if the fresh expiry had not started
        // the count over.
        var budget = SilentRetryBudget(window: .seconds(60), maximumAttempts: 2)
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(2)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(100)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(101)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(102)) == .retry(Self.target))
    }

    @Test
    func `A redirect for another page starts an episode of its own`() {
        // A second expiry somewhere else is a new episode and gets its own retry, rather than being read as the first
        // page's retry having failed.
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.otherTarget, at: start + .seconds(1)) == .retry(Self.otherTarget))
        #expect(budget.signInFormReached(redirectingTo: Self.otherTarget, at: start + .seconds(2)) == .confirmAppPassword(Self.otherTarget))
    }

    @Test
    func `While a check is in flight every redirect waits, whichever page it is for`() {
        var budget = SilentRetryBudget(confirmationTimeout: .seconds(120))
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(2)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.otherTarget, at: start + .seconds(3)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1 + 119)) == .wait)
    }

    @Test
    func `A check unanswered for longer than the confirmation timeout is presumed lost`() {
        // A check lost to a network failure is never answered, and waiting for it forever would leave the page on the
        // sign-in form for good.
        var budget = SilentRetryBudget(window: .seconds(60), confirmationTimeout: .seconds(120))
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1 + 121)) == .retry(Self.target))
    }

    @Test
    func `The redirects that signed a user out on 2026-10-09 ask the server, which keeps the account`() {
        // The limits are the ones both apps use, since what is replayed is what the app did. The offsets are measured
        // from the first redirect of the incident, at 03:00:34.991.
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))

        // 03:02:37.389, two minutes later: the window has lapsed, so this is a fresh expiry.
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .milliseconds(122_398)) == .retry(Self.target))

        // 03:02:43.983: the stale page's script navigating to the sign-in form after one of its polls got an HTTP 401,
        // which is what was taken for the retry having been refused.
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .milliseconds(128_992)) == .confirmAppPassword(Self.target))

        // The server was accepting the app password all along.
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .milliseconds(129_500)) == .retry(Self.target))

        // However long the script keeps that up, an accepting server keeps the account.
        var instant = start + .milliseconds(129_500)

        for _ in 0 ..< 100 {
            instant += .milliseconds(6594)
            let step = budget.signInFormReached(redirectingTo: Self.target, at: instant)

            #expect(step != .signOut)

            if step == .confirmAppPassword(Self.target) {
                instant += .milliseconds(500)
                #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: instant) != .signOut)
            }
        }
    }

    // MARK: - Answers About the App Password

    @Test(arguments: [AppPasswordVerdict.accepted, .undetermined])
    func `An accepted or undetermined app password never signs out, however the episode stands`(verdict: AppPasswordVerdict) {
        let start = ContinuousClock.now

        // Answering the check the episode asked for.
        var asked = SilentRetryBudget()
        _ = asked.signInFormReached(redirectingTo: Self.target, at: start)
        _ = asked.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))

        #expect(asked.appPasswordChecked(verdict, for: Self.target, at: start + .seconds(2)) != .signOut)

        // Answering after the server answered the page, which ended the episode.
        var answered = SilentRetryBudget()
        _ = answered.signInFormReached(redirectingTo: Self.target, at: start)
        _ = answered.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        _ = answered.responseArrived(from: Self.target, statusCode: 200, at: start + .seconds(2))

        #expect(answered.appPasswordChecked(verdict, for: Self.target, at: start + .seconds(3)) == .wait)

        // Answering after everything was forgotten, and for a page nothing concerns.
        var forgotten = SilentRetryBudget()
        _ = forgotten.signInFormReached(redirectingTo: Self.target, at: start)
        _ = forgotten.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        forgotten.reset()

        #expect(forgotten.appPasswordChecked(verdict, for: Self.target, at: start + .seconds(2)) == .wait)
        #expect(forgotten.appPasswordChecked(verdict, for: Self.otherTarget, at: start + .seconds(3)) == .wait)
    }

    @Test
    func `A rejected app password signs out`() {
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))

        #expect(budget.appPasswordChecked(.rejected, for: Self.target, at: start + .seconds(2)) == .signOut)
    }

    @Test
    func `A rejected app password signs out after a reset as well`() {
        // The rejection is the server's own answer, so nothing that happened to the episode meanwhile can outweigh it.
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        budget.reset()

        #expect(budget.appPasswordChecked(.rejected, for: Self.target, at: start + .seconds(2)) == .signOut)
    }

    @Test
    func `A rejected app password signs out after its episode was answered as well`() {
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        _ = budget.responseArrived(from: Self.target, statusCode: 200, at: start + .seconds(2))

        #expect(budget.appPasswordChecked(.rejected, for: Self.target, at: start + .seconds(3)) == .signOut)
    }

    @Test
    func `An accepted app password retries the page until the attempts run out, then holds`() {
        var budget = SilentRetryBudget(maximumAttempts: 3, firstHold: .seconds(60))
        let start = ContinuousClock.now

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(2)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(3)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(4)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(5)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(6)) == .hold(Self.target, for: .seconds(60)))
    }

    @Test
    func `An undetermined answer holds at once`() {
        // A server that cannot be asked cannot be asked again straight away either, however many attempts remain.
        var budget = SilentRetryBudget(maximumAttempts: 3, firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))

        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))
    }

    // MARK: - Holds

    @Test
    func `Each hold lasts twice as long as the one before, up to the longest`() {
        var budget = SilentRetryBudget(firstHold: .seconds(60), longestHold: .seconds(1800))
        var instant = ContinuousClock.now

        for seconds in [60, 120, 240, 480, 960, 1800, 1800] {
            let hold = Duration.seconds(seconds)

            #expect(budget.signInFormReached(redirectingTo: Self.target, at: instant) == .retry(Self.target))
            #expect(budget.signInFormReached(redirectingTo: Self.target, at: instant + .seconds(1)) == .confirmAppPassword(Self.target))
            #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: instant + .seconds(2)) == .hold(Self.target, for: hold))

            instant += .seconds(2) + hold + .seconds(1)
        }
    }

    @Test
    func `While a page is held its redirects wait, and another page's retry`() {
        var budget = SilentRetryBudget(firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(30)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.otherTarget, at: start + .seconds(31)) == .retry(Self.otherTarget))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(61)) == .wait)
    }

    @Test
    func `Once a hold has ended the page's next redirect starts a fresh episode`() {
        var budget = SilentRetryBudget(maximumAttempts: 3, firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(63)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(64)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.accepted, for: Self.target, at: start + .seconds(65)) == .retry(Self.target))
    }

    @Test
    func `A reset forgets the episode, the check in flight, the hold and how long the next one lasts`() {
        // A load the user asked for starts over, and must not be cancelled for something an earlier page went through.
        var budget = SilentRetryBudget(firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
        budget.reset()

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(2)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(3)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(4)) == .hold(Self.target, for: .seconds(60)))
        budget.reset()

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(5)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(6)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(7)) == .hold(Self.target, for: .seconds(60)))
    }

    // MARK: - Responses

    @Test
    func `An answer for the page ends the episode`() {
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)

        #expect(budget.responseArrived(from: Self.target, statusCode: 200, at: start + .seconds(1)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(2)) == .retry(Self.target))
    }

    @Test
    func `An answer for the page starts the holds over at the first one`() {
        var budget = SilentRetryBudget(firstHold: .seconds(60), longestHold: .seconds(1800))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(63)) == .retry(Self.target))
        #expect(budget.responseArrived(from: Self.target, statusCode: 200, at: start + .seconds(64)) == .wait)

        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(65)) == .retry(Self.target))
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(66)) == .confirmAppPassword(Self.target))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(67)) == .hold(Self.target, for: .seconds(60)))
    }

    @Test
    func `An HTTP 401 for the page asks the server`() {
        // Nextcloud answers a page request carrying a refused app password with HTTP 401 rather than with a redirect to
        // the sign-in form, so this is the response that can mean a refusal, and the server is asked what it means.
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)

        #expect(budget.responseArrived(from: Self.target, statusCode: 401, at: start + .seconds(1)) == .confirmAppPassword(Self.target))
    }

    @Test
    func `An HTTP 401 for the page while a check is in flight waits for that check`() {
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))

        #expect(budget.responseArrived(from: Self.target, statusCode: 401, at: start + .seconds(2)) == .wait)
    }

    @Test
    func `An HTTP 401 for the page after a check was presumed lost asks the server again`() {
        // A check whose answer never came must not leave every later 401 for the page waiting on it, or a page that is
        // only ever answered with 401 would never be asked about again.
        var budget = SilentRetryBudget(confirmationTimeout: .seconds(120))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1)) == .confirmAppPassword(Self.target))

        #expect(budget.responseArrived(from: Self.target, statusCode: 401, at: start + .seconds(122)) == .confirmAppPassword(Self.target))
    }

    @Test(arguments: [otherTarget, nil] as [URL?], [200, 401])
    func `A response for another page or for no address at all changes nothing`(url: URL?, statusCode: Int) {
        // A response the budget is not waiting for neither ends the episode nor asks the server anything, so the next
        // redirect for the page is still the suspicious one.
        var budget = SilentRetryBudget()
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)

        #expect(budget.responseArrived(from: url, statusCode: statusCode, at: start + .seconds(1)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(2)) == .confirmAppPassword(Self.target))
    }

    @Test
    func `An answer for a held page ends its hold`() {
        var budget = SilentRetryBudget(firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))

        #expect(budget.responseArrived(from: Self.target, statusCode: 200, at: start + .seconds(10)) == .wait)
        #expect(budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(11)) == .retry(Self.target))
    }

    @Test
    func `An HTTP 401 for a held page asks the server`() {
        var budget = SilentRetryBudget(firstHold: .seconds(60))
        let start = ContinuousClock.now

        _ = budget.signInFormReached(redirectingTo: Self.target, at: start)
        _ = budget.signInFormReached(redirectingTo: Self.target, at: start + .seconds(1))
        #expect(budget.appPasswordChecked(.undetermined, for: Self.target, at: start + .seconds(2)) == .hold(Self.target, for: .seconds(60)))

        #expect(budget.responseArrived(from: Self.target, statusCode: 401, at: start + .seconds(10)) == .confirmAppPassword(Self.target))
    }

    // MARK: - Properties Over Sequences of Events

    @Test(arguments: seeds)
    func `Whatever arrives in whatever order, only the server's refusal signs out`(seed: UInt64) {
        let record = Self.replay(seed: seed)

        for (index, entry) in record.enumerated() {
            if let verdict = entry.verdict {
                #expect((entry.step == .signOut) == (verdict == .rejected), "\(Self.transcript(of: record, through: index, seed: seed))")
            } else {
                #expect(entry.step != .signOut, "\(Self.transcript(of: record, through: index, seed: seed))")
            }
        }
    }

    @Test(arguments: seeds)
    func `Whatever arrives in whatever order, an episode's work stays bounded`(seed: UInt64) {
        let limits = SilentRetryBudget()
        let record = Self.replay(seed: seed)
        var unansweredCheckAskedAt: ContinuousClock.Instant?
        var retriesSinceExpiry = 0

        for (index, entry) in record.enumerated() {
            if entry.verdict != nil {
                unansweredCheckAskedAt = nil
            }

            switch entry.step {
                case .retry:
                    // A retry answered to a redirect starts an episode; one answered to a check is another attempt in it.
                    if entry.verdict == nil {
                        retriesSinceExpiry = 0
                    } else {
                        retriesSinceExpiry += 1
                        #expect(retriesSinceExpiry < limits.maximumAttempts, "\(Self.transcript(of: record, through: index, seed: seed))")
                    }

                case .confirmAppPassword:
                    // One check at a time, unless the one before it is presumed lost.
                    if let unansweredCheckAskedAt {
                        #expect(entry.instant - unansweredCheckAskedAt >= limits.confirmationTimeout, "\(Self.transcript(of: record, through: index, seed: seed))")
                    }

                    unansweredCheckAskedAt = entry.instant

                case let .hold(_, duration):
                    #expect(duration >= limits.firstHold, "\(Self.transcript(of: record, through: index, seed: seed))")
                    #expect(duration <= limits.longestHold, "\(Self.transcript(of: record, through: index, seed: seed))")

                case .wait, .signOut:
                    break
            }
        }
    }

    @Test
    func `The sequences of events reach every step there is, and holds that have grown`() {
        // The property cases above are only worth as much as the sequences they run over: a generator that never
        // reached a check or a hold would let them pass while proving nothing.
        let limits = SilentRetryBudget()
        var reached = Set<String>()
        var longestHold = Duration.zero

        for seed in Self.seeds {
            for entry in Self.replay(seed: seed) {
                switch entry.step {
                    case .retry:
                        reached.insert("retry")

                    case .confirmAppPassword:
                        reached.insert("confirmAppPassword")

                    case .wait:
                        reached.insert("wait")

                    case let .hold(_, duration):
                        reached.insert("hold")
                        longestHold = max(longestHold, duration)

                    case .signOut:
                        reached.insert("signOut")
                }
            }
        }

        #expect(reached == ["retry", "confirmAppPassword", "wait", "hold", "signOut"])
        #expect(longestHold > limits.firstHold)
    }

    ///
    /// `replay(seed:)` drives a budget with the limits both apps use through the sequence of events `seed` stands for, and records every call made with what the budget answered.
    ///
    /// Each event comes some time after the one before it, half of the time within five seconds, which keeps redirects inside the window often enough to reach checks and holds, and otherwise within 200 seconds, which reaches past the window, the confirmation timeout and the shorter holds.
    /// An event is a redirect to the sign-in form for one of two pages, a response for either page or for no address with a status of 200, 401, 503 or none, or an answer about the app password for the page a check was last asked for, accepted and undetermined each twice as likely as rejected.
    /// The answers arrive whether or not a check is in flight, so late answers to checks presumed lost and answers to nothing are part of what is replayed.
    /// A recorded `verdict` is the answer passed to the budget, and is `nil` for every call that was not one.
    ///
    private static func replay(seed: UInt64) -> [(call: String, verdict: AppPasswordVerdict?, step: SilentRetryStep, instant: ContinuousClock.Instant)] {
        var budget = SilentRetryBudget()
        var random = SplitMix64(seed: seed)
        var instant = ContinuousClock.now
        var lastConfirmed = target
        var record: [(call: String, verdict: AppPasswordVerdict?, step: SilentRetryStep, instant: ContinuousClock.Instant)] = []

        for _ in 0 ..< eventsPerSequence {
            let milliseconds = random.next(below: 2) == 0 ? random.next(below: 5001) : random.next(below: 200_001)
            instant += .milliseconds(milliseconds)
            let page = random.next(below: 2) == 0 ? target : otherTarget
            let call: String
            let verdict: AppPasswordVerdict?
            let step: SilentRetryStep

            switch random.next(below: 10) {
                case 0 ..< 4:
                    call = "signInFormReached(redirectingTo: \(page.lastPathComponent))"
                    verdict = nil
                    step = budget.signInFormReached(redirectingTo: page, at: instant)

                case 4 ..< 7:
                    let url = [page, nil][random.next(below: 2)]
                    let statusCode = [200, 401, 503, nil][random.next(below: 4)]
                    call = "responseArrived(from: \(url?.lastPathComponent ?? "nil"), statusCode: \(statusCode.map { "\($0)" } ?? "nil"))"
                    verdict = nil
                    step = budget.responseArrived(from: url, statusCode: statusCode, at: instant)

                default:
                    let answer = [AppPasswordVerdict.accepted, .accepted, .undetermined, .undetermined, .rejected][random.next(below: 5)]
                    call = "appPasswordChecked(\(answer), for: \(lastConfirmed.lastPathComponent))"
                    verdict = answer
                    step = budget.appPasswordChecked(answer, for: lastConfirmed, at: instant)
            }

            record.append((call: call, verdict: verdict, step: step, instant: instant))

            if case let .confirmAppPassword(confirmed) = step {
                lastConfirmed = confirmed
            }
        }

        return record
    }

    ///
    /// `transcript(of:through:seed:)` spells out the calls of `record` up to and including the one at `index`, each with when it was made after the first and what it was answered, so a failing property case says how the budget got there.
    ///
    private static func transcript(of record: [(call: String, verdict: AppPasswordVerdict?, step: SilentRetryStep, instant: ContinuousClock.Instant)], through index: Int, seed: UInt64) -> String {
        let calls = record[...index].map { "+\($0.instant - record[0].instant): \($0.call) -> \($0.step)" }

        return (["Seed \(seed):"] + calls).joined(separator: "\n")
    }
}
