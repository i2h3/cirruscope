// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Foundation
import Testing

/// `MulticolorAccentColorOracleTests` measures the two framework facts the recognition of "Multicolor" in `WebAccentColor.effective(in:)` rests on, rather than restating them.
struct MulticolorAccentColorOracleTests {
    /// `isMulticolor` is whether the machine running the tests has its macOS accent color set to "Multicolor", read from the global `AppleAccentColor` default, which is absent exactly then.
    static var isMulticolor: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleAccentColor"] == nil
    }

    @Test(arguments: [
        (NSAppearance.Name.aqua, "#2E6AF0"),
        (NSAppearance.Name.darkAqua, "#5A8DFF"),
    ])
    func `The accent color asset resolves by the name the property list gives AppKit`(appearanceName: NSAppearance.Name, hexString: String) throws {
        let name = try #require(Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String)
        let color = try #require(NSColor(named: name))
        let appearance = try #require(NSAppearance(named: appearanceName))
        var accentColor: WebAccentColor?

        appearance.performAsCurrentDrawingAppearance {
            accentColor = WebAccentColor(resolving: color)
        }

        #expect(accentColor?.hexString == hexString)
    }

    @Test(.enabled(if: isMulticolor, "The macOS accent color is not Multicolor on this machine"), arguments: [
        NSAppearance.Name.aqua,
        NSAppearance.Name.darkAqua,
    ])
    func `AppKit answers with the app's own accent color while the macOS accent color is Multicolor`(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))

        #expect(WebAccentColor.effective(in: appearance) == nil)
    }
}
