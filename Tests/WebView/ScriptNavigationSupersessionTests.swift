// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `ScriptNavigationSupersessionTests` measures what WebKit does with a load the app asked for when the page that load would replace navigates itself before the app has decided the load's navigation policy.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct ScriptNavigationSupersessionTests {
    @Test
    func `A held load released without the page navigating in between goes ahead`() async throws {
        let outcome = try await ScriptNavigationSupersessionProbe.measureHeldLoad()

        #expect(outcome.contentProcessTerminations == 0)
        #expect(outcome.decidedPaths == ["/page", "/retry"])
        #expect(outcome.requestedPaths == ["/page", "/retry"])
        #expect(outcome.heldLoadCallbacks == [.didStartProvisionalNavigation, .didCommit, .didFinish])
        #expect(outcome.documentPath == "/retry")
        #expect(outcome.reportedPath == "/retry")
    }

    @Test(arguments: ScriptNavigationTrigger.allCases)
    func `A held load is dropped without a word when the page it would replace navigates first`(trigger: ScriptNavigationTrigger) async throws {
        let outcome = try await ScriptNavigationSupersessionProbe.measureHeldLoad(supersededBy: trigger)

        #expect(outcome.contentProcessTerminations == 0)

        // The delegate is asked about the page's navigation to the sign-in form while the retry's decision is still held,
        // which is the sign-in form the app took for its retry's answer.
        #expect(outcome.decidedPaths == ["/page", "/retry", "/login"])

        // The retry is never requested, although its decision was `.allow`: answering it after the page navigated has
        // no effect at all, so the server can never have refused it.
        #expect(outcome.requestedPaths == ["/page"])

        // Nor is its navigation ever reported as started, committed, finished or failed, so nothing the app observes
        // through `WKNavigationDelegate` tells it the retry is gone.
        #expect(outcome.heldLoadCallbacks.isEmpty)

        // The stale page is still what the web view shows, and its `url` says so too rather than naming the retry.
        #expect(outcome.documentPath == "/page")
        #expect(outcome.reportedPath == "/page")
    }
}
