// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

/// `StoreAccessLock` is the lock `ExclusiveStoreAccess` holds for the whole of a test case, so that only one case at a time in the test process uses SwiftData.
///
/// It is an actor handing the lock from one waiter to the next rather than a `Mutex`, because the cases waiting for it run on the main actor while the migration cases holding it run off it, and a blocked main thread is what a synchronous migration on the main actor already deadlocked once.
/// A waiting case suspends instead, and the main thread stays free for whatever the case holding the lock needs from it.
///
/// Waiters are served in the order they arrived, so no case can be starved by others queuing behind it.
actor StoreAccessLock {
    /// `shared` is the one lock every case using SwiftData waits for, since what it guards is the whole test process's.
    static let shared = StoreAccessLock()

    /// `isLocked` is `true` while a case holds the lock, including the moment it is handed straight on to the next waiter.
    private var isLocked = false

    /// `waiters` are the cases waiting for the lock, oldest first.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// `acquire()` returns once the calling case holds the lock, suspending until then if another case holds it.
    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// `release()` hands the lock to the case that has waited longest, or unlocks it when nobody is waiting.
    func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }

        waiters.removeFirst().resume()
    }
}
