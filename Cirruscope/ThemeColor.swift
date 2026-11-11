// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ThemeColor` is a color a Nextcloud server's theming names as a CSS hex string, read into the three eight-bit sRGB components it encodes.
struct ThemeColor: Equatable {
    /// `red` is the red sRGB component, from `0` to `255`.
    let red: UInt8

    /// `green` is the green sRGB component, from `0` to `255`.
    let green: UInt8

    /// `blue` is the blue sRGB component, from `0` to `255`.
    let blue: UInt8

    /// `init?(hexString:)` reads `hexString` as `#rgb` or `#rrggbb`, or fails when it is anything else.
    init?(hexString: String) {
        guard hexString.hasPrefix("#") else {
            return nil
        }

        let digits = hexString.dropFirst()

        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }

        let sixDigits: String

        switch digits.count {
            case 3:
                sixDigits = digits.map { "\($0)\($0)" }.joined()
            case 6:
                sixDigits = String(digits)
            default:
                return nil
        }

        guard let value = UInt32(sixDigits, radix: 16) else {
            return nil
        }

        red = UInt8(truncatingIfNeeded: value >> 16)
        green = UInt8(truncatingIfNeeded: value >> 8)
        blue = UInt8(truncatingIfNeeded: value)
    }
}
