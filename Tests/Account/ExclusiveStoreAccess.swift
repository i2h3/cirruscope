// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Testing

/// `ExclusiveStoreAccess` is the trait every suite opening a SwiftData container carries, so that no two of its cases, nor a case of any other suite carrying it, use SwiftData at the same time.
///
/// SwiftData resolves a model by its entity name through state the whole process shares, and opening a container over a schema rewrites that state for every entity name the schema declares.
/// The app never notices, opening exactly one container per process, but the test process opens many, and the frozen nested copies in the shipped schemas reuse the live models' names (`Account`, `ServerApp`, `KeyboardShortcut`), because that is how a migration recognizes them.
/// On the iOS 26.5 Simulator, a store holding an unsaved `SchemaV2.Account` saved after an in-memory container over the live schema was opened, with nothing running concurrently, aborts the host on an uncaught `NSUnknownKeyException`: "the entity Account is not key value coding-compliant for the key "conversations"", a key only the live `Account` has.
/// The full iOS test action interleaved exactly that, the migration and import suites seeding frozen stores off the main actor while the main-actor suites opened `AccountStoreHarness` containers, and a different case died on every run, a live store's save aborting the same way.
/// Runs on the iOS 27.0 Simulator and on macOS 27 did not show it, which is not a reason to rely on it.
///
/// So a case holds `StoreAccessLock.shared` from before its suite is instantiated, which is where the harnesses open their containers, until it ends.
/// That is not much of a cost: the store suites run on the main actor with synchronous bodies, so they could not overlap each other anyway, and what the lock removes is only the overlap with the two suites seeding stores on disk.
/// Suites that never open a container do not carry it and keep running beside everything.
///
/// Forgetting it cannot pass unnoticed: `AccountStoreHarness` and `StoreFileHarness` record an issue whenever they open a container outside its scope, failing the case on every run instead of crashing an unrelated one on some.
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
