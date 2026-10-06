// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ThemeColor` is a color a Nextcloud server's theming names as a CSS hex string, read into the three eight-bit sRGB components it encodes.
///
/// Only the two forms Nextcloud itself validates its theming colors against are accepted, `#` followed by three or six hexadecimal digits in either case, so anything else, an image address above all, is not a color.
/// The components are kept as the eight bits the string encodes rather than as fractions, so the value is exactly what the server said.
/// It is here rather than in `Core/` because no widget draws a server's theme.
struct ThemeColor: Equatable {
    /// `red` is the red sRGB component, from `0` to `255`.
    let red: UInt8

    /// `green` is the green sRGB component, from `0` to `255`.
    let green: UInt8

    /// `blue` is the blue sRGB component, from `0` to `255`.
    let blue: UInt8

    /// `init?(hexString:)` reads `hexString` as `#rgb` or `#rrggbb`, or fails when it is anything else.
    ///
    /// Every digit is checked to be an ASCII hexadecimal digit before the integer parser sees it, because `UInt32(_:radix:)` also accepts a leading `+`, and a leading `-` in front of zero.
    /// The ASCII half of that check is defence in depth: `Character.isHexDigit` alone accepts fullwidth digits, which the integer parser happens to refuse as well.
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
