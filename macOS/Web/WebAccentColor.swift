// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `WebAccentColor` is the accent color the user chose in System Settings, in the two forms the Nextcloud web interface needs: an sRGB hex string, and the brightness verdict behind the handful of Nextcloud values that cannot be expressed in CSS at all.
struct WebAccentColor: Equatable {
    /// `logger` records failures to express an accent color in sRGB, and a missing accent color asset, under the `WebAccentColor` category.
    private static let logger = Logger(for: WebAccentColor.self)

    /// `hexString` is the color as an sRGB CSS hex string such as `#2E6AF0`.
    let hexString: String

    /// `isBright` is `true` when black text reads better on this color than white text does.
    let isBright: Bool

    /// `init?(resolving:)` converts `color` to sRGB and derives both members from it, or fails when the color has no sRGB representation.
    init?(resolving color: NSColor) {
        guard let sRGB = color.usingColorSpace(.sRGB) else {
            Self.logger.error("Could not express accent color in sRGB; the web view keeps Nextcloud's own primary color")
            return nil
        }

        let red = Self.eightBitComponent(sRGB.redComponent)
        let green = Self.eightBitComponent(sRGB.greenComponent)
        let blue = Self.eightBitComponent(sRGB.blueComponent)

        hexString = String(format: "#%02X%02X%02X", red, green, blue)
        isBright = Self.isBright(red: red, green: green, blue: blue)
    }

    /// `effective(in:)` resolves `NSColor.controlAccentColor` for `appearance` and returns it, or returns `nil` while the user's macOS accent color is "Multicolor" or when the color has no sRGB representation.
    static func effective(in appearance: NSAppearance) -> WebAccentColor? {
        let appAccentColorAsset = appAccentColorAsset()
        var controlAccentColor: WebAccentColor?
        var appAccentColor: WebAccentColor?

        appearance.performAsCurrentDrawingAppearance {
            controlAccentColor = WebAccentColor(resolving: NSColor.controlAccentColor)
            appAccentColor = appAccentColorAsset.flatMap { WebAccentColor(resolving: $0) }
        }

        return forwarded(controlAccentColor: controlAccentColor, appAccentColor: appAccentColor)
    }

    /// `forwarded(controlAccentColor:appAccentColor:)` decides which accent color reaches the page, given `NSColor.controlAccentColor` and the app's own accent color asset resolved in the same appearance: none when the two are equal, which is "Multicolor", and the control accent color otherwise.
    static func forwarded(controlAccentColor: WebAccentColor?, appAccentColor: WebAccentColor?) -> WebAccentColor? {
        guard let controlAccentColor else {
            return nil
        }

        guard controlAccentColor != appAccentColor else {
            logger.debug("The macOS accent color is Multicolor; the web view keeps Nextcloud's own primary color")
            return nil
        }

        return controlAccentColor
    }

    /// `appAccentColorAsset()` returns the app's own accent color, the asset `NSAccentColorName` names in the property list, or `nil` when the property list names none or the asset catalog lacks it.
    ///
    /// Either failure turns the recognition of "Multicolor" off, so it is logged as an error rather than passing unnoticed.
    private static func appAccentColorAsset() -> NSColor? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String else {
            logger.error("The property list names no accent color; Multicolor cannot be told apart from a chosen accent color")
            return nil
        }

        guard let color = NSColor(named: name) else {
            logger.error("The accent color asset \(name, privacy: .public) is missing; Multicolor cannot be told apart from a chosen accent color")
            return nil
        }

        return color
    }

    /// `eightBitComponent(_:)` scales one clamped sRGB color component to the `0...255` range CSS hex notation encodes.
    private static func eightBitComponent(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }

    /// `isBright(red:green:blue:)` answers whether a color built from these eight-bit sRGB components contrasts too weakly with white for white text to be readable on it.
    private static func isBright(red: Int, green: Int, blue: Int) -> Bool {
        let luminance = 0.2126 * relativeLuminanceComponent(red) + 0.7152 * relativeLuminanceComponent(green) + 0.0722 * relativeLuminanceComponent(blue)
        return 1.05 / (luminance + 0.05) < 4.5
    }

    /// `relativeLuminanceComponent(_:)` linearizes one gamma-encoded eight-bit sRGB component into the value the WCAG relative-luminance sum expects.
    private static func relativeLuminanceComponent(_ eightBitComponent: Int) -> Double {
        let component = Double(eightBitComponent) / 255

        if component <= 0.03928 {
            return component / 12.92
        }

        return pow((component + 0.055) / 1.055, 2.4)
    }
}
