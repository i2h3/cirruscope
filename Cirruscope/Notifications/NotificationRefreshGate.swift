// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `NotificationRefreshGate` decides whether a request to fetch the notifications starts a pass now, waits for the pass already running, or belongs to a session that has since ended.
///
/// The live monitor is asked to refresh from several directions at once — the stream connecting, the stream reporting a change, the app coming back to the front, a panel closing — and overlapping fetches could land in either order.
/// So at most one pass runs at a time, a request arriving during one turns into exactly one more pass after it, and every request belongs to a generation that stopping or restarting the monitor moves on, so a pass of an ended session can neither run again nor end the current one's.
/// It is a value with no clock and no tasks, so the rule is tested on its own rather than through the monitor.
/// It lives in `Cirruscope/` because only `NotificationMonitor` uses it, and the widget extension watches nothing live.
///
struct NotificationRefreshGate: Equatable, Sendable {
    ///
    /// `generation` is the session a pass belongs to, moved on by `advance()`.
    ///
    private(set) var generation: UInt64 = 0

    ///
    /// `isRunning` is whether a pass of the current generation is under way.
    ///
    private var isRunning = false

    ///
    /// `isRequestedAgain` is whether a request arrived while that pass was under way, owing one more pass once it ends.
    ///
    private var isRequestedAgain = false

    ///
    /// `advance()` ends the current generation, forgetting any pass under way and any pass owed.
    ///
    mutating func advance() {
        generation &+= 1
        isRunning = false
        isRequestedAgain = false
    }

    ///
    /// `request()` answers whether a pass should start now, recording one more pass instead while one is already under way.
    ///
    mutating func request() -> Bool {
        guard isRunning == false else {
            isRequestedAgain = true
            return false
        }

        isRunning = true
        return true
    }

    ///
    /// `finish(_:)` is called when a pass of `generation` ends, and answers whether another pass is owed and should run straight away.
    ///
    /// A pass of an earlier generation changes nothing and is owed nothing, the gate having been reset under it.
    ///
    mutating func finish(_ generation: UInt64) -> Bool {
        guard generation == self.generation else {
            return false
        }

        guard isRequestedAgain else {
            isRunning = false
            return false
        }

        isRequestedAgain = false
        return true
    }
}
