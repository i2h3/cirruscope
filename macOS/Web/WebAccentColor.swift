// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `WebAccentColor` is the accent color the user chose in System Settings, in the two forms the Nextcloud web interface needs: an sRGB hex string, and the brightness verdict behind the handful of Nextcloud values that cannot be expressed in CSS at all.
///
/// `WebViewController.appearanceAttributeScript()` builds one with `effective(in:)` and hands both members to `macOSScript.appearanceAttributes`, which writes them onto `<html>` as the `--cirruscope-accent-color` custom property and the `data-cirruscope-accent-bright` attribute. `Cirruscope.css` re-derives Nextcloud's whole primary color family from just those two.
/// Only two members cross into the page because the arithmetic belongs in the stylesheet. Nextcloud computes its primary family in PHP and emits ten literal hex values, but its `Util::mix()` is a weighted average in gamma-encoded sRGB and its `lighten()`/`darken()` are offsets of sRGB-HSL lightness — which `color-mix(in srgb, …)` and `hsl(from … calc(l ± n))` reproduce exactly — so the derivations live next to the rest of the Nextcloud-specific CSS instead of here. `isBright` is the exception that must be resolved natively: `--primary-invert-if-bright` and `--primary-invert-if-dark` hold the keywords `invert(100%)` and `no` rather than colors, and no CSS function turns a color into a keyword. It also supplies the sign of the hover step, which Nextcloud moves away from the text color rather than consistently darker.
/// While the user's macOS accent color is "Multicolor", AppKit answers `NSColor.controlAccentColor` with the app's own `AccentColor` asset instead. That is Cirruscope's brand rather than a choice the user made, so `effective(in:)` withholds it, and the page keeps the primary color the user or the administrator chose on the server (issue #93).
/// The type is deliberately not `@MainActor`. `NSColor` is `Sendable` and `NSAppearance` carries no actor isolation, so the block `effective(in:)` hands to AppKit is never inferred main-actor-isolated and the dynamic isolation check the "Concurrency" section of `AGENTS.md` warns about is not involved here at all.
struct WebAccentColor: Equatable {
    /// `logger` records failures to express an accent color in sRGB, and a missing accent color asset, under the `WebAccentColor` category.
    private static let logger = Logger(for: WebAccentColor.self)

    /// `hexString` is the color as an sRGB CSS hex string such as `#2E6AF0`.
    ///
    /// `WebViewController.appearanceAttributeScript()` interpolates it into a JavaScript string literal without escaping anything, which is safe only because this value can contain nothing but `#` followed by six uppercase hexadecimal digits. That is why the `#RRGGBB` form is chosen over `rgb()` — no quote, backslash, or semicolon can ever appear in it — and why `WebAccentColorTests` pins the shape rather than only the values.
    /// The alpha channel is discarded: a translucent primary element would let whatever Nextcloud paints behind it bleed through, which is never what forwarding an accent color means.
    let hexString: String

    /// `isBright` is `true` when black text reads better on this color than white text does.
    ///
    /// It is a port of Nextcloud's `Util::invertTextColor()` — `colorContrast($color, '#ffffff') < 4.5` over the WCAG relative luminance computed by `Util::calculateLuma()` — so the branch Cirruscope takes and the branch the server would have taken agree. `Cirruscope.css` keys the two `--primary-invert-if-*` filter keywords, the sign of `--color-primary-element-hover`'s lightness step, and the literal `--color-primary-element-text-dark` on it.
    /// It is computed from the same eight-bit components `hexString` is formatted from, not from the raw floating-point ones, so it can never disagree with the color the page actually receives.
    let isBright: Bool

    /// `init?(resolving:)` converts `color` to sRGB and derives both members from it, or fails when the color has no sRGB representation.
    ///
    /// `effective(in:)` calls it with `NSColor.controlAccentColor` and with the app's own accent color asset while an appearance is current; the tests call it with fixed colors. Components are clamped before being scaled to eight bits because converting a wide-gamut color into sRGB can land outside `0…1`, which would otherwise format as a malformed token.
    /// Failing rather than substituting a fallback color is deliberate: it leaves the stylesheet's `data-cirruscope-accent` gate closed, so the page keeps Nextcloud's own theme color, which still looks intentional in a way a guessed color would not. Only a pattern color lacks a color space and `controlAccentColor` is a catalog color, so this is an anomaly worth retrieving from the log store later rather than an expected state.
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
    ///
    /// `WebViewController.appearanceAttributeScript()` calls it with its own web view's `effectiveAppearance`, so the color forwarded into the page is the one the window actually draws with: the matching form of the chosen system accent, and the increased-contrast form when the user has enabled that.
    /// "Multicolor" is recognized by comparing colors rather than by reading what the user chose. Under it, AppKit answers `controlAccentColor` with the app's own accent color asset, so the two are resolved in the same appearance and compared at the eight-bit precision the page receives; equal means AppKit is answering with Cirruscope's brand color, and that is withheld. The asset is looked up by the name `NSAccentColorName` gives it in the property list, the key AppKit itself reads, so the comparison follows the build setting rather than restating its value. The global `AppleAccentColor` default would answer more directly, but it is undocumented, its values have already grown beyond the eight colors, and reading what the system wrote falls outside the reason the privacy manifest declares for reading user defaults; see `DECISIONS.md`.
    /// The trade-offs accepted are that a custom accent color identical to the brand color at that precision counts as "Multicolor", and that an increased-contrast adjustment AppKit might make to the app's own color would defeat the comparison and forward the brand color, as 1.1.0 and 1.2.0 did.
    /// The conversions have to happen *inside* the block. A dynamic catalog color such as `controlAccentColor` resolves against `NSAppearance.currentDrawingAppearance`, so resolving it outside would silently answer for whichever appearance happened to be current. `performAsCurrentDrawingAppearance(_:)` runs its block synchronously and restores the previously current appearance afterwards, and is used in place of the `NSAppearance.currentAppearance` setter deprecated in macOS 12.
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
    ///
    /// It is the decision alone, separated from `effective(in:)` so that tests can pin it without depending on the accent color the machine running them has chosen in System Settings.
    /// A missing asset forwards the control accent color, because "Multicolor" cannot be recognized without it and forwarding is what 1.1.0 and 1.2.0 did.
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
    ///
    /// This is Nextcloud's `Util::invertTextColor()` written out: the contrast ratio against white is `1.05 / (luminance + 0.05)`, since white's own relative luminance is `1.0`, and Nextcloud's threshold for flipping to black text is the WCAG minimum of `4.5`.
    private static func isBright(red: Int, green: Int, blue: Int) -> Bool {
        let luminance = 0.2126 * relativeLuminanceComponent(red) + 0.7152 * relativeLuminanceComponent(green) + 0.0722 * relativeLuminanceComponent(blue)
        return 1.05 / (luminance + 0.05) < 4.5
    }

    /// `relativeLuminanceComponent(_:)` linearizes one gamma-encoded eight-bit sRGB component into the value the WCAG relative-luminance sum expects.
    ///
    /// The piecewise transfer function and its `0.03928` threshold are copied from Nextcloud's `Util::calculateLuma()` rather than from the WCAG text, which rounds the same constant differently, so `isBright(red:green:blue:)` cannot disagree with the server about a color sitting on the boundary.
    private static func relativeLuminanceComponent(_ eightBitComponent: Int) -> Double {
        let component = Double(eightBitComponent) / 255

        if component <= 0.03928 {
            return component / 12.92
        }

        return pow((component + 0.055) / 1.055, 2.4)
    }
}
