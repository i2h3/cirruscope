// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `DockBadgeLabelTests` covers the label the Dock icon shows for an unread notification count.
///
/// It exists because the Dock badge is a string the Mac has to keep narrow, unlike the iPhone's, which is an integer the system lays out itself, and the cap is a deliberate difference between the two that must not be lost when either side changes.
///
struct DockBadgeLabelTests {
    @Test(arguments: [0, -1])
    func `Nothing unread shows no badge at all`(count: Int) {
        #expect(DockBadge.label(for: count) == nil)
    }

    @Test(arguments: [1, 42, 999])
    func `A count up to 999 is shown as it is, in the current locale's digits`(count: Int) {
        #expect(DockBadge.label(for: count) == count.formatted())
    }

    @Test(arguments: [1000, 1500, Int.max])
    func `A count past 999 is shortened to 999+`(count: Int) {
        #expect(DockBadge.label(for: count) == "999+")
    }
}
