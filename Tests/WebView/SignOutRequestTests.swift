// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing
import WebKit

/// `SignOutRequestTests` covers `SignOutRequest`, which decides whether a navigation to the connected server's sign-out route is the user asking to sign out or the page's own script.
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
