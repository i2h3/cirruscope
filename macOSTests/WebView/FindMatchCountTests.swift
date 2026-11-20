// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `FindMatchCountTests` covers `FindBarViewController.matchCountText(matchFound:currentMatch:matchCount:)`, the pure rendering of a find result, the current match number and the page-wide match count into the find bar's label, which is the only part of the find bar that can be exercised without a live web view (issue #98).
@MainActor
struct FindMatchCountTests {
    @Test
    func `A query that matched nothing shows a label`() {
        // Not asserted against the literal, which is localized and so follows the test machine's language.
        #expect(FindBarViewController.matchCountText(matchFound: false, currentMatch: 0, matchCount: 0).isEmpty == false)
    }

    @Test
    func `A query that matched shows the current match and the total`() {
        let text = FindBarViewController.matchCountText(matchFound: true, currentMatch: 2, matchCount: 5)

        // The numbers themselves are not localized, so they can be asserted directly.
        #expect(text.isEmpty == false)
        #expect(text.contains("2"))
        #expect(text.contains("5"))
    }

    @Test
    func `A query that matched without a count clears the label`() {
        #expect(FindBarViewController.matchCountText(matchFound: true, currentMatch: 1, matchCount: 0) == "")
    }
}
