// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import CoreGraphics
import Foundation
import ImageIO
import Testing

/// `PlatedArtworkTests` covers the two ways of filling the donated plate that are not an app's glyph: a collective's emoji, and a conversation's own picture.
///
/// It asserts colour and opacity rather than shape, for the reason `ServerAppIconThumbnailTests` does: the bug this artwork exists to prevent was never about geometry. A donated bitmap leaves the process and is composited by something that will not tint it and will not put anything behind it, so a plate that lets the background through hands the question of whether the picture can be seen back to whatever is behind it. Both new paths can lose that independently — the emoji one by dropping the plate, the compositing one by letting a picture's own alpha channel through — and neither loss is visible in a test of the layout.
///
/// It is a shared suite rather than a macOS one because neither path touches `glyphColor()`, which is the only part of this artwork either platform has to answer for itself. It reads pixels through `CGImageSource` for the same reason.
struct PlatedArtworkTests {
    /// `edge` is the bitmap's width and height in pixels.
    private var edge: Int {
        Int(ServerAppIconThumbnail.size * 2)
    }

    /// `pixel(of:x:y:)` reads back one pixel of a PNG, addressed from the top-left corner as it would be seen.
    ///
    /// Through `CGImageSource` and a one-pixel context rather than a platform image type, so this runs against both SDKs.
    private func pixel(of data: Data, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes: [UInt8] = [0, 0, 0, 0]
        let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))

        // The pixel of interest is brought under the one-pixel context by translating the whole image
        // under it, with y flipped because Core Graphics counts from the bottom and this addresses from the top.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))

        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// `picture(_:alpha:)` is a solid one-colour bitmap standing in for whatever a server sent.
    private func picture(_ color: CGColor, alpha: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))

        context.setAlpha(alpha)
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

        return try #require(context.makeImage())
    }

    @Test
    func `An emoji is drawn as a PNG of the same size as an app's icon`() throws {
        let data = try #require(ServerAppIconThumbnail.pngData(drawingEmoji: "📗"))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(image.width == edge)
        #expect(image.height == edge)
    }

    @Test
    func `An emoji sits on the same opaque white plate an app's glyph does`() throws {
        let data = try #require(ServerAppIconThumbnail.pngData(drawingEmoji: "📗"))
        // Just inside the plate's right edge, clear of both the traffic lights and the emoji.
        let body = try pixel(of: data, x: edge - Int(Double(edge) * 0.12), y: edge / 2)

        #expect(body.alpha == 255)
        #expect(body.red > 240)
        #expect(body.green > 240)
        #expect(body.blue > 240)
    }

    /// An emoji carries its own colours, so the one thing that must *not* happen is it coming out as a silhouette in the glyph ink.
    @Test
    func `An emoji keeps its own colours rather than being drawn as one flat ink`() throws {
        let data = try #require(ServerAppIconThumbnail.pngData(drawingEmoji: "🟥"))
        let centre = try pixel(of: data, x: edge / 2, y: edge / 2)

        #expect(centre.red > 150)
        #expect(centre.red > centre.green)
        #expect(centre.red > centre.blue)
    }

    @Test
    func `A composited picture covers the middle of the plate`() throws {
        let red = try picture(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), alpha: 1)
        let data = try #require(ServerAppIconThumbnail.pngData(compositing: red))
        let centre = try pixel(of: data, x: edge / 2, y: edge / 2)

        #expect(centre.alpha == 255)
        #expect(centre.red > 200)
        #expect(centre.green < 60)
        #expect(centre.blue < 60)
    }

    /// The property the whole plate exists for, and the one a composited picture is most likely to lose: a picture with an alpha channel of its own must not make the artwork see-through.
    @Test
    func `A picture that is itself transparent still yields an opaque result`() throws {
        let ghost = try picture(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), alpha: 0)
        let data = try #require(ServerAppIconThumbnail.pngData(compositing: ghost))
        let centre = try pixel(of: data, x: edge / 2, y: edge / 2)

        #expect(centre.alpha == 255)
        #expect(centre.red > 240)
        #expect(centre.green > 240)
        #expect(centre.blue > 240)
    }
}
