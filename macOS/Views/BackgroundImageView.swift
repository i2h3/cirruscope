// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `BackgroundImageView` is an `NSImageView` that paints the themed backdrop: a plain color filling its bounds, and over it an image scaled to fill them and center-cropped, matching the CSS `background-color` and `background-size: cover` of Nextcloud's own background rather than the aspect-fit scaling `NSImageView` offers.
///
/// `WebViewController` uses it for the backdrop shown behind the web view during the initial page load; with neither a color nor an image assigned it draws nothing, letting the window material show through.
class BackgroundImageView: NSImageView {
    /// `backdropColor` is the plain color filled behind the image, or `nil` to fill nothing.
    ///
    /// It is a fixed color rather than a dynamic one because Nextcloud paints a plain background identically in its light and dark themes.
    var backdropColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_: NSRect) {
        if let backdropColor {
            backdropColor.setFill()
            bounds.fill()
        }

        guard let image, image.size.width > 0, image.size.height > 0 else {
            return
        }

        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)

        image.draw(in: NSRect(origin: origin, size: size))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
}
