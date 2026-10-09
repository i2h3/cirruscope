// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

///
/// `ScriptNavigationSupersessionTests` measures what WebKit does with a load the app asked for when the page that load would replace navigates itself before the app has decided the load's navigation policy.
///
/// That race is what signed a user out on 9 October 2026 while the server still accepted their app password.
/// The browser session behind a web view had lapsed, so the page was sent to Nextcloud's sign-in form, and the app answered by re-requesting the page with the app password.
/// Before the app's decision on that re-request was in, its main thread being busy, the stale page's own script navigated to the sign-in form again, as it does on every HTTP 401 its polls receive.
/// The app read that second arrival as its retry having been refused and signed out.
/// What WebKit makes of a load superseded that way is a belief about WebKit — by its source, `FrameLoader::loadWithDocumentLoader` stops the pending policy check through `PolicyChecker::stopCheck` — so it is measured here, the way `SecurityOriginProbe` measures origins, rather than restated.
/// `ScriptNavigationSupersessionProbe` drives a real `WKWebView` against documents a `WKURLSchemeHandler` serves and records, holds the retry's decision as the busy main thread did, and lets the stale page navigate before releasing it.
/// The first case is the control that keeps the others honest: the same held decision, released without the page navigating in between, does load, so a retry that never arrives in the others is the page's doing and not the probe's.
/// The time limit turns a step that never happens into a failure rather than a run that never ends, and each superseded case takes the probe's whole ten-second observation window by design.
///
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
