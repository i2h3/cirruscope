// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import CoreGraphics
import os

/// This extension resolves the colour the Mac fills a donated app glyph with.
extension ServerAppIconThumbnail {
    /// `glyphColor()` is the colour the app's glyph is filled with: the secondary label colour, resolved in the light appearance.
    ///
    /// The light one always, and deliberately. The plate is white whatever the system is set to, so the ink on it has to be the one meant for a light surface; resolving it in the current appearance would produce pale grey on white the moment the user switched to dark, which is the same class of bug this whole type exists to fix.
    static func glyphColor() -> CGColor? {
        var resolved: CGColor?

        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor.secondaryLabelColor.usingColorSpace(.sRGB)?.cgColor
        }

        guard let resolved else {
            logger.error("The secondary label colour could not be resolved; no thumbnail will be drawn")
            return nil
        }

        return resolved
    }
}
