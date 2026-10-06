// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ThemeColorTests` covers `ThemeColor(hexString:)`, which reads the plain background color a Nextcloud server's theming names for the Mac's web windows to fill their loading backdrop with.
///
/// The input is a string the server composed, and the same stored value holds an image address whenever the theme is not a plain color, so what matters as much as reading a color correctly is refusing everything that is not one: a wrongly accepted string would paint a bogus color behind the loading card.
/// The rejected cases include the signed numbers the parser checks digits for explicitly, `#+12345` and `#-00000`, which the integer parser would otherwise read as numbers, and fullwidth digits, which `Character.isHexDigit` alone would admit.
struct ThemeColorTests {
    @Test(arguments: [
        // Nextcloud's default background color.
        ("#00679e", 0x00, 0x67, 0x9E),
        ("#00679E", 0x00, 0x67, 0x9E),
        // The short form expands each digit.
        ("#abc", 0xAA, 0xBB, 0xCC),
        ("#ABC", 0xAA, 0xBB, 0xCC),
        // The endpoints.
        ("#000000", 0x00, 0x00, 0x00),
        ("#ffffff", 0xFF, 0xFF, 0xFF),
        ("#fff", 0xFF, 0xFF, 0xFF),
    ] as [(String, UInt8, UInt8, UInt8)])
    func `A hex color reads into its components`(hexString: String, red: UInt8, green: UInt8, blue: UInt8) throws {
        let color = try #require(ThemeColor(hexString: hexString))

        #expect(color.red == red)
        #expect(color.green == green)
        #expect(color.blue == blue)
    }

    @Test(arguments: [
        "",
        "#",
        "00679e",
        "#00679",
        "#0067",
        "#00679e0",
        "#00679eff",
        "#ggg",
        "#00679g",
        "#+12345",
        "#-12345",
        "#-00000",
        "#ＡＢＣ",
        " #00679e",
        "#00679e ",
        "https://cloud.example.com/apps/theming/img/background/jo-myoung-hee-fluid.webp",
        "/apps/theming/img/background/jo-myoung-hee-fluid.webp",
        "rgb(0, 103, 158)",
    ])
    func `Anything other than a three- or six-digit hex color is refused`(hexString: String) {
        #expect(ThemeColor(hexString: hexString) == nil)
    }
}
