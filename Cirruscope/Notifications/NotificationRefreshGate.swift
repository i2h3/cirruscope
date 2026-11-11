// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NotificationRefreshGate` decides whether a request to fetch the notifications starts a pass now, waits for the pass already running, or belongs to a session that has since ended.
struct NotificationRefreshGate: Equatable, Sendable {
    /// `generation` is the session a pass belongs to, moved on by `advance()`.
    private(set) var generation: UInt64 = 0

    /// `isRunning` is whether a pass of the current generation is under way.
    private var isRunning = false

    /// `isRequestedAgain` is whether a request arrived while that pass was under way, owing one more pass once it ends.
    private var isRequestedAgain = false

    /// `advance()` ends the current generation, forgetting any pass under way and any pass owed.
    mutating func advance() {
        generation &+= 1
        isRunning = false
        isRequestedAgain = false
    }

    /// `request()` answers whether a pass should start now, recording one more pass instead while one is already under way.
    mutating func request() -> Bool {
        guard isRunning == false else {
            isRequestedAgain = true
            return false
        }

        isRunning = true
        return true
    }

    /// `finish(_:)` is called when a pass of `generation` ends, and answers whether another pass is owed and should run straight away.
    ///
    /// A pass of an earlier generation changes nothing and is owed nothing, the gate having been reset under it.
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
