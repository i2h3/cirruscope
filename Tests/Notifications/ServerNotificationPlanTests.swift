// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerNotificationPlanTests` covers the decision of what one fetch of the server's notifications means for Notification Center: what is posted, what is withdrawn, and what is remembered.
///
/// It exists because every way this decision goes wrong is visible and none of them crashes: an old notification announced as new, the whole queue announced at once on a first look, a notification announced twice, one left on screen after it was dealt with, or another account's notification shown to whoever signed in since.
/// The worked cases pin each rule, the property cases assert over arbitrary records, listings and Notification Center contents that the rules never contradict each other, and the last case runs a model of a server whose notifications arrive, are dismissed and slide in and out of the newest part it answers with, asserting that nothing is ever announced twice.
///
struct ServerNotificationPlanTests {
    ///
    /// `alice` is the recipient most cases decide for.
    ///
    private static let alice = ServerNotificationRecipient(ServerNotificationFixture.alice)

    ///
    /// `seeds` are the fixed seeds the property cases draw their inputs from, so a failure names the seed that reproduces it.
    ///
    private static let seeds: [UInt64] = Array(0 ..< 200)

    // MARK: - The first look at an account

    @Test
    func `The first look at an account posts nothing and records what it found`() {
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([3, 5, 4]), for: Self.alice, recorded: nil, delivered: [], mayPost: true)

        #expect(plan.isBaseline)
        #expect(plan.post.isEmpty)
        #expect(plan.record == ServerNotificationFixture.record([3, 4, 5], highWater: 5, for: ServerNotificationFixture.alice))
    }

    @Test
    func `The first look at an account still withdraws what the server no longer lists`() {
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([3]), for: Self.alice, recorded: nil, delivered: [ServerNotificationFixture.delivered(2, for: ServerNotificationFixture.alice), ServerNotificationFixture.delivered(3, for: ServerNotificationFixture.alice)], mayPost: true)

        #expect(plan.withdraw == [2])
    }

    @Test(arguments: [ServerNotificationFixture.bob, ServerNotificationFixture.otherServer])
    func `A record made for another account counts as none`(other: ServerAccount) {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: other)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.isBaseline)
        #expect(plan.post.isEmpty)
        #expect(plan.record.recipient == Self.alice)
    }

    @Test
    func `A new app password for the same login keeps the record`() {
        // The record names the login, not the app password: a sign-in that replaces the credential without a sign-out,
        // such as the Mac asking for one after the Keychain refused a read, must not make the next fetch a first look,
        // which would silently swallow whatever arrived in between. A sign-out forgets the record, so the fetch after
        // it is one.
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: ServerNotificationRecipient(ServerNotificationFixture.aliceNewPassword), recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.isBaseline == false)
        #expect(plan.post.map(\.id) == [2])
    }

    // MARK: - Posting

    @Test
    func `A later look posts what the record did not list, oldest first`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let listing = [ServerNotificationFixture.item(1), ServerNotificationFixture.item(3, createdMinutesAfterReference: 10), ServerNotificationFixture.item(2, createdMinutesAfterReference: 20)]
        let plan = ServerNotificationPlan.make(listing: listing, for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.isBaseline == false)
        #expect(plan.post.map(\.id) == [3, 2])
    }

    @Test
    func `Notifications created at the same moment are posted in the order of their identifiers`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let listing = [ServerNotificationFixture.item(1), ServerNotificationFixture.item(4, createdMinutesAfterReference: 9), ServerNotificationFixture.item(3, createdMinutesAfterReference: 9)]
        let plan = ServerNotificationPlan.make(listing: listing, for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.map(\.id) == [3, 4])
    }

    @Test
    func `A look while posting is withheld records and withdraws without posting`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(1, for: ServerNotificationFixture.alice)], mayPost: false)

        #expect(plan.isBaseline == false)
        #expect(plan.post.isEmpty)
        #expect(plan.withdraw == [1])
        #expect(plan.record == ServerNotificationFixture.record([2], highWater: 2, for: ServerNotificationFixture.alice))
    }

    @Test
    func `What a look withheld is not posted by the next one`() {
        // The Mac with a web window open, and the iPhone in front, see a notification arrive without announcing it;
        // closing the window, or leaving the app, must not announce it late.
        let first = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: Self.alice, recorded: ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice), delivered: [], mayPost: false)
        let second = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: Self.alice, recorded: first.record, delivered: [], mayPost: true)

        #expect(second.post.isEmpty)
    }

    @Test
    func `The record is replaced by each look rather than added to`() {
        let recorded = ServerNotificationFixture.record([1, 2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2, 3]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.record.notificationIDs == [2, 3])
        #expect(plan.record.highWater == 3)
    }

    @Test
    func `A notification tapped away from Notification Center is not posted again`() {
        // Tapping a notification removes it from Notification Center without dismissing it on the server, so the
        // record, not Notification Center, is what says it was already announced.
        let recorded = ServerNotificationFixture.record([1, 2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.isEmpty)
    }

    @Test
    func `A notification Notification Center still holds is not posted again even when the record lost it`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1, 2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(2, for: ServerNotificationFixture.alice)], mayPost: true)

        #expect(plan.post.isEmpty)
    }

    // MARK: - Notifications coming back into view

    @Test
    func `An older notification the server lists again is not taken for a new one`() {
        // The server answers with its newest notifications only, so dismissing newer ones lets an older one move back
        // into the answer. Its identifier is below the highest one recorded, which is what gives it away.
        let recorded = ServerNotificationFixture.record([10, 11, 12], highWater: 12, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([4, 10, 13]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.map(\.id) == [13])
    }

    @Test
    func `Notifications the server left out of a listing for a while are not posted again when they return`() {
        // The server leaves out the notifications of an app that is switched off, and lists them again once it is
        // switched back on; the lowest number of the shorter listing must not become the floor they are measured by.
        let recorded = ServerNotificationFixture.record(Set([90] + Array(100 ... 120)), highWater: 120, for: ServerNotificationFixture.alice)
        let shorter = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([90]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)
        let returned = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([90] + Array(100 ... 120)), for: Self.alice, recorded: shorter.record, delivered: [], mayPost: true)

        #expect(shorter.post.isEmpty)
        #expect(returned.post.isEmpty)
    }

    @Test
    func `The same list again after an empty answer posts nothing`() {
        let recorded = ServerNotificationFixture.record([5, 6], highWater: 6, for: ServerNotificationFixture.alice)
        let empty = ServerNotificationPlan.make(listing: [], for: Self.alice, recorded: recorded, delivered: [], mayPost: true)
        let again = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([5, 6]), for: Self.alice, recorded: empty.record, delivered: [], mayPost: true)

        #expect(empty.record == ServerNotificationFixture.record([], highWater: 6, for: ServerNotificationFixture.alice))
        #expect(again.post.isEmpty)
    }

    @Test
    func `A new notification after everything was dismissed is posted`() {
        let recorded = ServerNotificationFixture.record([], highWater: 6, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([7]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.map(\.id) == [7])
    }

    @Test
    func `The first notification an account ever receives is posted`() {
        let recorded = ServerNotificationFixture.record([], highWater: nil, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([1]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.map(\.id) == [1])
    }

    // MARK: - Withdrawing

    @Test
    func `A delivered notification the server no longer lists is withdrawn, and one it lists is kept`() {
        let recorded = ServerNotificationFixture.record([1, 2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(1, for: ServerNotificationFixture.alice), ServerNotificationFixture.delivered(2, for: ServerNotificationFixture.alice)], mayPost: true)

        #expect(plan.withdraw == [1])
    }

    @Test(arguments: [ServerNotificationFixture.bob, ServerNotificationFixture.otherServer])
    func `A delivered notification posted for another account is withdrawn although the server lists its number`(other: ServerAccount) {
        let recorded = ServerNotificationFixture.record([2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(2, for: other)], mayPost: true)

        #expect(plan.withdraw == [2])
    }

    @Test
    func `A notification delivered before notifications recorded their account is kept while listed and withdrawn once not`() {
        let recorded = ServerNotificationFixture.record([1, 2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(1, for: nil), ServerNotificationFixture.delivered(2, for: nil)], mayPost: true)

        #expect(plan.withdraw == [1])
        #expect(plan.post.isEmpty)
    }

    // MARK: - Edges

    @Test
    func `An empty answer records nothing listed and keeps the highest number seen`() {
        let recorded = ServerNotificationFixture.record([3], highWater: 9, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: [], for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.record == ServerNotificationFixture.record([], highWater: 9, for: ServerNotificationFixture.alice))
    }

    @Test
    func `An unchanged answer leaves the record equal`() {
        let recorded = ServerNotificationFixture.record([1, 2], highWater: 2, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2, 1]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.record == recorded)
        #expect(plan.post.isEmpty)
        #expect(plan.withdraw.isEmpty)
    }

    @Test
    func `A notification listed twice is posted once`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2, 2, 1]), for: Self.alice, recorded: recorded, delivered: [], mayPost: true)

        #expect(plan.post.map(\.id) == [2])
    }

    @Test
    func `A plan without posting keeps its withdrawals and its record`() {
        let recorded = ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice)
        let plan = ServerNotificationPlan.make(listing: ServerNotificationFixture.items([2]), for: Self.alice, recorded: recorded, delivered: [ServerNotificationFixture.delivered(1, for: ServerNotificationFixture.alice)], mayPost: true)
        let withheld = plan.withoutPosting()

        #expect(plan.post.isEmpty == false)
        #expect(withheld.post.isEmpty)
        #expect(withheld.withdraw == plan.withdraw)
        #expect(withheld.record == plan.record)
        #expect(withheld.isBaseline == plan.isBaseline)
    }

    // MARK: - Properties

    @Test(arguments: seeds)
    func `No arbitrary look contradicts the rules`(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        let others = [ServerNotificationFixture.bob, ServerNotificationFixture.otherServer]

        let listedIDs = Self.draw(upTo: 8, from: 1 ... 30, using: &generator)
        let listing = listedIDs.map { ServerNotificationFixture.item($0, createdMinutesAfterReference: generator.next(below: 50)) }

        let recorded: ServerNotificationRecord?

        switch generator.next(below: 3) {
            case 0:
                recorded = nil

            case 1:
                recorded = ServerNotificationFixture.record(Set(Self.draw(upTo: 8, from: 1 ... 30, using: &generator)), highWater: generator.next(below: 31), for: others[generator.next(below: 2)])

            default:
                let ids = Set(Self.draw(upTo: 8, from: 1 ... 30, using: &generator))
                recorded = ServerNotificationFixture.record(ids, highWater: ids.max().map { $0 + generator.next(below: 3) }, for: ServerNotificationFixture.alice)
        }

        let delivered = Self.draw(upTo: 6, from: 1 ... 30, using: &generator).map { id in
            switch generator.next(below: 3) {
                case 0:
                    ServerNotificationFixture.delivered(id, for: nil)

                case 1:
                    ServerNotificationFixture.delivered(id, for: others[generator.next(below: 2)])

                default:
                    ServerNotificationFixture.delivered(id, for: ServerNotificationFixture.alice)
            }
        }

        let mayPost = generator.next(below: 2) == 0
        let plan = ServerNotificationPlan.make(listing: listing, for: Self.alice, recorded: recorded, delivered: delivered, mayPost: mayPost)

        let postedIDs = Set(plan.post.map(\.id))
        let kept = Set(delivered.map(\.id)).subtracting(plan.withdraw)
        let transcript = "seed \(seed): listed \(listedIDs), recorded \(String(describing: recorded)), delivered \(delivered), mayPost \(mayPost), plan \(plan)"

        #expect(postedIDs.isSubset(of: Set(listedIDs)), "\(transcript)")
        #expect(plan.post.count == postedIDs.count, "\(transcript)")
        #expect(postedIDs.isDisjoint(with: kept), "\(transcript)")

        if let recorded, recorded.recipient == Self.alice {
            #expect(postedIDs.isDisjoint(with: recorded.notificationIDs), "\(transcript)")
        }

        if plan.isBaseline || mayPost == false {
            #expect(plan.post.isEmpty, "\(transcript)")
        }

        for item in delivered where Set(listedIDs).contains(item.id) && (item.recipient == nil || item.recipient == Self.alice) {
            #expect(plan.withdraw.contains(item.id) == false, "\(transcript)")
        }

        let deliveredAfter = kept.map { ServerNotificationFixture.delivered($0, for: ServerNotificationFixture.alice) } + plan.post.map { ServerNotificationFixture.delivered($0.id, for: ServerNotificationFixture.alice) }
        let again = ServerNotificationPlan.make(listing: listing, for: Self.alice, recorded: plan.record, delivered: deliveredAfter, mayPost: true)

        #expect(again.post.isEmpty, "\(transcript)")
        #expect(again.record == plan.record, "\(transcript)")
    }

    @Test(arguments: seeds)
    func `A server whose notifications come and go never has one announced twice`(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        var queue: [Int] = []
        var nextID = 1
        var recorded: ServerNotificationRecord?
        var delivered: Set<Int> = []
        var everPosted: Set<Int> = []
        var everListed: Set<Int> = []
        var highestListed = 0

        for step in 0 ..< 60 {
            for _ in 0 ..< generator.next(below: 4) {
                queue.append(nextID)
                nextID += 1
            }

            queue.removeAll { _ in generator.next(below: 5) == 0 }

            // The server answers with its 25 newest notifications, now and then with nothing at all, and now and then
            // leaves some out for a while, as it does for an app that is switched off.
            let hidden = generator.next(below: 8) == 0 ? Set(queue.filter { _ in generator.next(below: 2) == 0 }) : []
            let listedIDs = generator.next(below: 12) == 0 ? [] : Array(queue.filter { hidden.contains($0) == false }.sorted(by: >).prefix(25))
            let listing = listedIDs.map { ServerNotificationFixture.item($0) }
            let mayPost = generator.next(below: 4) != 0

            let plan = ServerNotificationPlan.make(listing: listing, for: Self.alice, recorded: recorded, delivered: delivered.map { ServerNotificationFixture.delivered($0, for: ServerNotificationFixture.alice) }, mayPost: mayPost)
            let postedIDs = Set(plan.post.map(\.id))
            let transcript = "seed \(seed), step \(step): listed \(listedIDs.sorted()), recorded \(String(describing: recorded)), delivered \(delivered.sorted()), posted \(postedIDs.sorted())"

            #expect(postedIDs.isDisjoint(with: everPosted), "\(transcript)")
            #expect(postedIDs.isDisjoint(with: everListed), "\(transcript)")

            if mayPost, plan.isBaseline == false {
                for id in listedIDs where id > highestListed {
                    #expect(postedIDs.contains(id), "\(transcript)")
                }
            }

            everPosted.formUnion(postedIDs)
            everListed.formUnion(listedIDs)
            highestListed = max(highestListed, listedIDs.max() ?? 0)
            recorded = plan.record
            delivered = delivered.subtracting(plan.withdraw).union(postedIDs)

            // The user clears a notification from Notification Center now and then without dismissing it on the server.
            delivered = delivered.filter { _ in generator.next(below: 6) != 0 }
        }
    }

    // MARK: - Helpers

    ///
    /// `draw(upTo:from:using:)` is up to `count` distinct numbers drawn from `range`, in the order drawn.
    ///
    private static func draw(upTo count: Int, from range: ClosedRange<Int>, using generator: inout SplitMix64) -> [Int] {
        var drawn: [Int] = []

        for _ in 0 ..< generator.next(below: count + 1) {
            let value = range.lowerBound + generator.next(below: range.count)

            if drawn.contains(value) == false {
                drawn.append(value)
            }
        }

        return drawn
    }
}
