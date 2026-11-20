// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `FindMatchCountTests` covers `FindBarViewController.matchCountText(matchFound:matchCount:)`, the pure rendering of a find result and the page-wide match count into the find bar's label, which is the only part of the find bar that can be exercised without a live web view (issue #98).
@MainActor
struct FindMatchCountTests {
    @Test
    func `A query that matched nothing shows a label`() {
        // Not asserted against the literal, which is localized and so follows the test machine's language.
        #expect(FindBarViewController.matchCountText(matchFound: false, matchCount: 0).isEmpty == false)
    }

    @Test
    func `A query that matched shows the match count`() {
        let text = FindBarViewController.matchCountText(matchFound: true, matchCount: 5)

        // The count itself is not localized, so it can be asserted directly.
        #expect(text.isEmpty == false)
        #expect(text.contains("5"))
    }

    @Test
    func `A query that matched without a count clears the label`() {
        #expect(FindBarViewController.matchCountText(matchFound: true, matchCount: 0) == "")
    }
}
