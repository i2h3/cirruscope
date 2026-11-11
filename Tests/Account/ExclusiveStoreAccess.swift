// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Testing

/// `ExclusiveStoreAccess` is the trait every suite opening a SwiftData container carries, so that no two of its cases, nor a case of any other suite carrying it, use SwiftData at the same time.
struct ExclusiveStoreAccess: SuiteTrait, TestTrait, TestScoping {
    /// `isHeld` is `true` inside a case running with this trait's lock held, which is what the harnesses check before opening a container.
    @TaskLocal
    static var isHeld = false

    /// `isRecursive` is `true` so a suite's trait reaches each of its cases, the lock being held per case rather than for a whole suite whose cases may wait on each other.
    var isRecursive: Bool {
        true
    }

    /// `provideScope(for:testCase:performing:)` runs one case with the lock held, releasing it however the case ends.
    ///
    /// A case already holding the lock, as one carrying the trait both from its suite and on its own would, runs as it is, since waiting for itself would never end.
    func provideScope(for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        guard Self.isHeld == false else {
            try await function()
            return
        }

        await StoreAccessLock.shared.acquire()

        do {
            try await Self.$isHeld.withValue(true) {
                try await function()
            }
        } catch {
            await StoreAccessLock.shared.release()
            throw error
        }

        await StoreAccessLock.shared.release()
    }

    /// `recordIfNotHeld(opening:sourceLocation:)` records an issue when a harness is about to open a container outside this trait's scope, naming the harness so the fix is obvious from the failure.
    static func recordIfNotHeld(opening harness: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard isHeld == false else {
            return
        }

        Issue.record("\(harness) opened a SwiftData container in a suite without `.exclusiveStoreAccess`; add it to the suite's traits so no other suite uses SwiftData at the same time.", sourceLocation: sourceLocation)
    }
}

extension Trait where Self == ExclusiveStoreAccess {
    /// `exclusiveStoreAccess` runs each case of the suite or test it is applied to with no other case in the process using SwiftData.
    static var exclusiveStoreAccess: Self {
        Self()
    }
}
