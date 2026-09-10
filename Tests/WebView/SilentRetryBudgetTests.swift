// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `SilentRetryBudgetTests` covers `SilentRetryBudget`, the one silent retry a web view is allowed while working through a lapsed browser session.
///
/// This is the bookkeeping both apps previously got wrong, in opposite directions and with the same result, which is why it is now one type with a suite of its own. Spending the budget when it should not be spent signs a user out of a valid account and makes them sign in again on every device they use; failing to spend it turns a genuinely rejected app password into a redirect loop.
/// Time is passed in rather than read, so the window can be tested without waiting for it.
///
struct SilentRetryBudgetTests {
    ///
    /// The page a retry is made for in most cases below.
    ///
    private static let target = URL(string: "https://cloud.example.com/apps/files/")!

    ///
    /// A different page, for the cases about a budget spent on one not being spent on another.
    ///
    private static let otherTarget = URL(string: "https://cloud.example.com/apps/spreed/")!

    @Test
    func `A fresh budget is unspent`() {
        let budget = SilentRetryBudget()

        #expect(budget.isSpent(on: Self.target) == false)
    }

    @Test
    func `A retry that has just gone out is outstanding`() {
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)

        #expect(budget.isSpent(on: Self.target, at: now))
    }

    @Test
    func `A retry of one page leaves another page's budget alone`() {
        // A second expiry somewhere else is a new episode and gets its own retry; without this, one unlucky page
        // would spend the budget for the whole session.
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)

        #expect(budget.isSpent(on: Self.otherTarget, at: now) == false)
    }

    @Test
    func `A retry the server answered is no longer outstanding`() {
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)
        budget.releaseIfAnswered(by: Self.target)

        #expect(budget.isSpent(on: Self.target, at: now) == false)
    }

    @Test
    func `Something else answering does not retire the retry`() {
        // A sub-frame of the document being navigated away from can answer while the retry is still in flight, and
        // letting it release the budget would re-arm the retry before its own outcome is known.
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)
        budget.releaseIfAnswered(by: Self.otherTarget)

        #expect(budget.isSpent(on: Self.target, at: now))
    }

    @Test
    func `A response with no address at all retires nothing`() {
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)
        budget.releaseIfAnswered(by: nil)

        #expect(budget.isSpent(on: Self.target, at: now))
    }

    @Test
    func `A retry that is never answered stops being outstanding once it cannot still be in flight`() {
        // The case that cost users their session: a retry lost to a network failure is never answered and never
        // released, and the address it was made for is the page they are most likely to come back to.
        var budget = SilentRetryBudget(window: .seconds(60))
        let issued = ContinuousClock.now

        budget.spend(on: Self.target, at: issued)

        #expect(budget.isSpent(on: Self.target, at: issued.advanced(by: .seconds(59))))
        #expect(budget.isSpent(on: Self.target, at: issued.advanced(by: .seconds(61))) == false)
    }

    @Test
    func `A released budget is unspent whether or not anything answered`() {
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)
        budget.release()

        #expect(budget.isSpent(on: Self.target, at: now) == false)
    }

    @Test
    func `Spending again moves the budget to the new page`() {
        var budget = SilentRetryBudget()
        let now = ContinuousClock.now

        budget.spend(on: Self.target, at: now)
        budget.spend(on: Self.otherTarget, at: now)

        #expect(budget.isSpent(on: Self.otherTarget, at: now))
        #expect(budget.isSpent(on: Self.target, at: now) == false)
    }
}
