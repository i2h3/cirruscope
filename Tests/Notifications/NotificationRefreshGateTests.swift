// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `NotificationRefreshGateTests` covers the rule that keeps the notification monitor's fetches from overlapping without ever dropping a request or wedging.
///
/// It exists because both ways this rule fails are silent: overlapping fetches whose answers land in the wrong order, or a gate left believing a pass is running, after which the monitor never fetches again for the rest of the session.
/// Every answer is taken into a constant before it is asserted, the gate being a value its calls change.
///
struct NotificationRefreshGateTests {
    @Test
    func `A request while nothing runs starts a pass`() {
        var gate = NotificationRefreshGate()
        let starts = gate.request()

        #expect(starts)
    }

    @Test
    func `Requests during a pass become exactly one more pass after it`() {
        var gate = NotificationRefreshGate()
        let first = gate.request()
        let second = gate.request()
        let third = gate.request()
        let owed = gate.finish(gate.generation)
        let owedAgain = gate.finish(gate.generation)

        #expect(first)
        #expect(second == false)
        #expect(third == false)
        #expect(owed)
        #expect(owedAgain == false)
    }

    @Test
    func `A pass that ends with nothing owed lets the next request start at once`() {
        var gate = NotificationRefreshGate()
        let first = gate.request()
        let owed = gate.finish(gate.generation)
        let next = gate.request()

        #expect(first)
        #expect(owed == false)
        #expect(next)
    }

    @Test
    func `Ending the session lets the next session's first request start although a pass was running`() {
        var gate = NotificationRefreshGate()
        let first = gate.request()
        gate.advance()
        let next = gate.request()

        #expect(first)
        #expect(next)
    }

    @Test
    func `A pass of an ended session neither runs again nor ends the current one's`() {
        var gate = NotificationRefreshGate()
        _ = gate.request()
        let ended = gate.generation
        _ = gate.request()

        gate.advance()
        let current = gate.request()
        let endedOwed = gate.finish(ended)
        let duringCurrent = gate.request()
        let currentOwed = gate.finish(gate.generation)

        #expect(current)
        #expect(endedOwed == false)
        #expect(duringCurrent == false)
        #expect(currentOwed)
    }
}
