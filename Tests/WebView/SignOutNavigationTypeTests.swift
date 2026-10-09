// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing
import WebKit

///
/// `SignOutNavigationTypeTests` measures the `WKNavigationType` WebKit reports for each way a page can reach the connected server's sign-out route, and pins that `SignOutRequest` reads each of them as it is meant to.
///
/// Both apps used to sign out, and revoke the app password, on any main-frame navigation to the route.
/// Nextcloud's session heartbeat with `auto_logout` set assigns the route to `location.href` from a timer once the page has gone without input for the session's lifetime, so an idle window signed its user out, and `SignOutRequest` now honours the route only when a link was activated.
/// That rests on a belief about WebKit — by its source, `NavigationAction.cpp` reports a link activated by a click event, trusted or synthetic, as `LinkClicked` and a location assignment or an app's own load as `Other` — so it is measured here, the way `ScriptNavigationSupersessionTests` measures WebKit, rather than restated.
/// `NavigationTypeProbe` drives a real `WKWebView` against a page a `WKURLSchemeHandler` serves and cancels the navigation, so no case ever leaves the page.
/// A real click cannot be synthesized, so the user choosing Nextcloud's "Log out" is approximated by the app's own script calling that link's `click()`; what makes it a link activation is the click event, which a real click delivers too.
/// The iOS app decides through `WebPage`, whose navigation decider is handed a `WKNavigationType` as well; what is measured here is a `WKWebView` on both platforms, on the understanding that `WebPage` passes on what its web view reports.
/// The time limit turns a step that never happens into a failure rather than a run that never ends.
///
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct SignOutNavigationTypeTests {
    @Test(arguments: [NavigationTypeTrigger.pageTimerAssignment, .evaluatedAssignment, .appLoad])
    func `Assigning the location or loading the sign-out route is reported as other and keeps the account`(trigger: NavigationTypeTrigger) async throws {
        let outcome = try await NavigationTypeProbe.measure(trigger)

        #expect(outcome.contentProcessTerminations == 0)
        #expect(outcome.requestedPaths == ["/page"])
        #expect(outcome.signOutWindowRequests.isEmpty)

        // Whether the page's own timer assigns the location without a user gesture, as Nextcloud's session heartbeat
        // does, or the app's evaluated script does with one, the gesture does not make it a link activation.
        #expect(outcome.signOutActions == [RecordedNavigationAction(navigationType: .other, target: .mainFrame)])

        for action in outcome.signOutActions {
            #expect(SignOutRequest.of(action.navigationType) == .scripted)
        }
    }

    @Test
    func `Activating the sign-out link is reported as link activation and signs out`() async throws {
        let outcome = try await NavigationTypeProbe.measure(.evaluatedLinkClick)

        #expect(outcome.contentProcessTerminations == 0)
        #expect(outcome.requestedPaths == ["/page"])
        #expect(outcome.signOutWindowRequests.isEmpty)
        #expect(outcome.signOutActions == [RecordedNavigationAction(navigationType: .linkActivated, target: .mainFrame)])

        for action in outcome.signOutActions {
            #expect(SignOutRequest.of(action.navigationType) == .explicit)
        }
    }

    @Test
    func `The page's own script activating the sign-out link is reported as link activation as well, which is the limitation SignOutRequest names`() async throws {
        let outcome = try await NavigationTypeProbe.measure(.pageTimerLinkClick)

        #expect(outcome.contentProcessTerminations == 0)
        #expect(outcome.requestedPaths == ["/page"])
        #expect(outcome.signOutWindowRequests.isEmpty)

        // Without a user gesture, and from a timer, a synthetic click on a link is still a link activation, so this
        // is read as the user signing out. Nothing in Nextcloud does it; should something start to, this is where
        // `SignOutRequest` would have to learn to tell the two apart.
        #expect(outcome.signOutActions == [RecordedNavigationAction(navigationType: .linkActivated, target: .mainFrame)])

        for action in outcome.signOutActions {
            #expect(SignOutRequest.of(action.navigationType) == .explicit)
        }
    }

    @Test
    func `Activating a sign-out link that asks for a new window is reported as link activation to both delegates and never as a main-frame navigation`() async throws {
        let outcome = try await NavigationTypeProbe.measure(.evaluatedNewWindowLinkClick)

        #expect(outcome.contentProcessTerminations == 0)
        #expect(outcome.requestedPaths == ["/page"])

        // The navigation delegate is asked first, with no target frame, which the Mac app's navigation delegate
        // allows on to its UI delegate and the iOS app's decider decides like a main-frame navigation.
        #expect(outcome.signOutActions == [RecordedNavigationAction(navigationType: .linkActivated, target: .newWindow)])

        // The UI delegate is then asked for a window, which is where the Mac app decides the route for a link like
        // this, and it is told the same type.
        #expect(outcome.signOutWindowRequests == [.linkActivated])

        for navigationType in outcome.signOutActions.map(\.navigationType) + outcome.signOutWindowRequests {
            #expect(SignOutRequest.of(navigationType) == .explicit)
        }
    }
}
