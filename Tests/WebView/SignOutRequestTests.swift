// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing
import WebKit

///
/// `SignOutRequestTests` covers `SignOutRequest`, which decides whether a navigation to the connected server's sign-out route is the user asking to sign out or the page's own script.
///
/// Getting it wrong one way revokes a working app password whenever an idle page's `auto_logout` fires, which is what it exists to stop; getting it wrong the other way leaves Nextcloud's own "Log out" doing nothing.
/// What WebKit actually reports for each way of reaching the route is measured separately, by `SignOutNavigationTypeTests`.
///
struct SignOutRequestTests {
    @Test
    func `Activating a link to the sign-out route is an explicit sign-out`() {
        #expect(SignOutRequest.of(.linkActivated) == .explicit)
    }

    @Test(arguments: [WKNavigationType.other, .formSubmitted, .backForward, .reload, .formResubmitted])
    func `Reaching the sign-out route any other way keeps the account`(navigationType: WKNavigationType) {
        #expect(SignOutRequest.of(navigationType) == .scripted)
    }
}
