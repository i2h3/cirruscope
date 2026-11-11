// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// `ServerAppIconThumbnail` draws the picture of a Nextcloud app that Spotlight and the Shortcuts app are given: a small white window, three traffic lights in its top-left corner, and the app's own glyph centred in the body below them.
///
/// It exists because those two surfaces are the only ones that draw a downloaded icon *literally*. Everywhere else in the app an icon is a template image, which AppKit tints for the appearance it is drawn in; a donated bitmap leaves the process and is composited by something that will not tint it, so a bare glyph is legible in one appearance and nearly invisible in the other. That was the bug: black on black.
enum ServerAppIconThumbnail {
    /// `size` is the edge length, in points, of the artwork handed to Spotlight and Shortcuts.
    ///
    /// Larger than anything those surfaces are known to draw, because they decide their own size and scaling down is the direction that costs nothing.
    static let size: CGFloat = 64

    /// `shadowMarginFraction` is how much of the bitmap's edge is left empty around the plate, so the shadow has somewhere to fall instead of being clipped.
    private static let shadowMarginFraction: CGFloat = 0.07

    /// `shadowBlurFraction` is the shadow's blur radius as a share of the bitmap's edge.
    private static let shadowBlurFraction: CGFloat = 0.035

    /// `cornerRadiusFraction` is the plate's corner radius as a share of its own width, chosen to sit alongside the rounded rectangles macOS draws its own icons as.
    private static let cornerRadiusFraction: CGFloat = 0.20

    /// `trafficLightDiameterFraction` is a traffic light's diameter as a share of the plate's width.
    private static let trafficLightDiameterFraction: CGFloat = 0.095

    /// `glyphSideFraction` is the edge of the square the app's glyph is fitted into, as a share of the plate's width.
    private static let glyphSideFraction: CGFloat = 0.46

    /// `trafficLightColors` are the close, minimize and zoom colours, in that order.
    private static let trafficLightColors = [
        CGColor(srgbRed: 1.0, green: 0.21961, blue: 0.23529, alpha: 1),
        CGColor(srgbRed: 1.0, green: 0.8, blue: 0.0, alpha: 1),
        CGColor(srgbRed: 0.20392, green: 0.78039, blue: 0.34902, alpha: 1),
    ]

    /// `logger` records thumbnail drawing under the `ServerAppIconThumbnail` category.
    /// It is `internal` rather than `private` because `glyphColor()` logs through it from this type's per-platform extension files.
    static let logger = Logger(for: ServerAppIconThumbnail.self)

    /// `pngData(forAppID:serverAddress:)` is the windowed icon of one app as PNG bytes, or `nil` if no icon has been cached for it or it cannot be drawn.
    static func pngData(forAppID appID: String, serverAddress: URL) -> Data? {
        guard let glyph = ServerAppIcons.shared.glyph(forAppID: appID, serverAddress: serverAddress) else {
            return nil
        }

        return pngData(drawing: glyph)
    }

    /// `pngData(drawing:)` is the artwork on its own, separate from the lookup so that what it draws can be asserted against actual pixels.
    ///
    /// That matters more here than it looks: the two ways this could silently go back to being unreadable — the plate losing its opacity, and the glyph losing its contrast against it — are both invisible to a test of the geometry and obvious to a test of the colours.
    static func pngData(drawing glyph: SVGGlyph) -> Data? {
        guard let ink = glyphColor() else {
            return nil
        }

        return pngData { context, box in
            context.setFillColor(ink)

            for shape in glyph.shapes(fittedIn: box) {
                context.addPath(shape.path)
                context.fillPath(using: shape.fillRule)
            }
        }
    }

    /// `pngData(forEmoji:orAppID:serverAddress:)` is the artwork for something the user gave an emoji, falling back to the icon of the app that owns it.
    ///
    /// Collectives and their pages are the things that have one, and an emoji is the better picture precisely where a shared app mark is the weaker one: a search that answers with six pages of one collective shows six identical marks, where the emoji is the thing the person chose to tell them apart by. The fallback is not a lesser answer but the same answer the other domains give, for the pages nobody has decorated.
    static func pngData(forEmoji emoji: String?, orAppID appID: String, serverAddress: URL) -> Data? {
        guard let emoji else {
            return pngData(forAppID: appID, serverAddress: serverAddress)
        }

        guard emoji.isEmpty == false else {
            return pngData(forAppID: appID, serverAddress: serverAddress)
        }

        guard let data = pngData(drawingEmoji: emoji) else {
            logger.error("An emoji could not be drawn onto the plate; falling back to the icon of app \(appID, privacy: .public)")
            return pngData(forAppID: appID, serverAddress: serverAddress)
        }

        return data
    }

    /// `pngData(drawingEmoji:)` is the artwork with `emoji` in the window's body instead of an app's glyph.
    static func pngData(drawingEmoji emoji: String) -> Data? {
        pngData { context, box in
            let font = CTFontCreateWithName("AppleColorEmoji" as CFString, box.height, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            guard bounds.width > 0, bounds.height > 0 else {
                return
            }

            // Fitted to whichever edge binds rather than to the height alone: an emoji is not reliably square,
            // and one scaled by its height can still be wider than the body it is meant to sit inside.
            let scale = min(box.width / bounds.width, box.height / bounds.height)

            context.saveGState()
            context.translateBy(x: box.midX, y: box.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    /// `pngData(compositing:)` is a picture the server drew, made into artwork this app can donate.
    static func pngData(compositing image: CGImage) -> Data? {
        let edge = size * 2
        let margin = edge * shadowMarginFraction
        let plate = CGRect(x: margin, y: margin, width: edge - margin * 2, height: edge - margin * 2)
        let radius = plate.width * cornerRadiusFraction

        guard let context = CGContext(data: nil, width: Int(edge), height: Int(edge), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        let shape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -edge * 0.012), blur: edge * shadowBlurFraction, color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(shape)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.draw(image, in: fill(CGSize(width: image.width, height: image.height), into: plate))
        context.restoreGState()

        guard let composed = context.makeImage() else {
            return nil
        }

        return pngData(of: composed)
    }

    /// `fill(_:into:)` is where a picture of `size` goes to cover `box` entirely, centred, with whatever does not fit hanging off the edges.
    private static func fill(_ size: CGSize, into box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return box
        }

        let scale = max(box.width / size.width, box.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)

        return CGRect(x: box.midX - scaled.width / 2, y: box.midY - scaled.height / 2, width: scaled.width, height: scaled.height)
    }

    /// `pngData(drawingBodyIn:)` draws the window and hands `body` the box its contents belong in, then encodes the result.
    ///
    /// The window is one drawing however it is filled, so it is written once: an app's glyph and a user's emoji differ only in what goes in the body, and two copies of the plate would be two places for the artwork to drift.
    private static func pngData(drawingBodyIn body: (CGContext, CGRect) -> Void) -> Data? {
        let edge = size * 2
        let margin = edge * shadowMarginFraction
        let plate = CGRect(x: margin, y: margin, width: edge - margin * 2, height: edge - margin * 2)
        let radius = plate.width * cornerRadiusFraction

        guard let context = CGContext(data: nil, width: Int(edge), height: Int(edge), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // The plate, under a soft shadow. Saved and restored around it so nothing drawn on top of the
        // window casts one of its own.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -edge * 0.012), blur: edge * shadowBlurFraction, color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        let diameter = plate.width * trafficLightDiameterFraction
        let lightsCenterY = plate.maxY - plate.height * 0.145

        for (index, color) in trafficLightColors.enumerated() {
            let x = plate.minX + plate.width * 0.11 + CGFloat(index) * diameter * 1.65
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: x, y: lightsCenterY - diameter / 2, width: diameter, height: diameter))
        }

        // The glyph is centred in the body — between the underside of the traffic lights and the bottom of
        // the plate — rather than on the plate as a whole, which read as sitting noticeably low.
        let bodyCenterY = (lightsCenterY - diameter / 2 + plate.minY) / 2
        let side = plate.width * glyphSideFraction
        let box = CGRect(x: plate.midX - side / 2, y: bodyCenterY - side / 2, width: side, height: side)

        body(context, box)

        guard let composed = context.makeImage() else {
            return nil
        }

        return pngData(of: composed)
    }

    /// `pngData(of:)` encodes a rendered bitmap as PNG bytes.
    private static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            logger.error("A PNG destination could not be created; no thumbnail will be drawn")
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            logger.error("The thumbnail could not be encoded as PNG")
            return nil
        }

        return data as Data
    }
}
