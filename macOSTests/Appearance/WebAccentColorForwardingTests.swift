// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebAccentColorForwardingTests` covers `WebAccentColor.forwarded(controlAccentColor:appAccentColor:)`, the decision whether the accent color AppKit answers with reaches the Nextcloud web interface at all.
///
/// While the macOS accent color is "Multicolor", AppKit answers `NSColor.controlAccentColor` with the app's own accent color asset, and forwarding that painted Cirruscope's brand color over the primary color chosen on the server (issue #93).
/// The decision is separated from `WebAccentColor.effective(in:)` precisely so it can be pinned here: `effective(in:)` reads whichever accent color the machine running the tests has chosen in System Settings, which `MulticolorAccentColorOracleTests` measures by agreement instead.
/// The one-step-off case is what pins the comparison as exact at the eight-bit precision the page receives, rather than a tolerance that would also swallow a chosen accent color close to the brand color.
struct WebAccentColorForwardingTests {
    @Test(arguments: [
        // Multicolor: AppKit answers with the app's own asset, light and dark.
        (NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), nil),
        (NSColor(srgbRed: 90 / 255, green: 141 / 255, blue: 255 / 255, alpha: 1), NSColor(srgbRed: 90 / 255, green: 141 / 255, blue: 255 / 255, alpha: 1), nil),
        // A chosen system accent color, light and dark.
        (NSColor(srgbRed: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1), NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), "#007AFF"),
        (NSColor(srgbRed: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1), NSColor(srgbRed: 90 / 255, green: 141 / 255, blue: 255 / 255, alpha: 1), "#0A84FF"),
        // Graphite.
        (NSColor(srgbRed: 140 / 255, green: 140 / 255, blue: 140 / 255, alpha: 1), NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), "#8C8C8C"),
        // One eight-bit step away from the brand color is a choice, not Multicolor.
        (NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 241 / 255, alpha: 1), NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), "#2E6AF1"),
        // A missing asset cannot tell Multicolor apart, so the control accent color is forwarded as before.
        (NSColor(srgbRed: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1), nil, "#007AFF"),
    ] as [(NSColor, NSColor?, String?)])
    func `Only an accent color other than the app's own is forwarded`(controlAccentColor: NSColor, appAccentColor: NSColor?, hexString: String?) throws {
        let control = try #require(WebAccentColor(resolving: controlAccentColor))
        let app = appAccentColor.flatMap { WebAccentColor(resolving: $0) }

        #expect(WebAccentColor.forwarded(controlAccentColor: control, appAccentColor: app)?.hexString == hexString)
    }

    @Test
    func `No control accent color forwards nothing`() {
        let app = WebAccentColor(resolving: NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1))

        #expect(WebAccentColor.forwarded(controlAccentColor: nil, appAccentColor: app) == nil)
    }
}
