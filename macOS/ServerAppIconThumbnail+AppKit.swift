// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import CoreGraphics
import os

/// This extension resolves the colour the Mac fills a donated app glyph with.
///
/// It is the one part of the artwork that could not be shared. Everything else about the plate — its geometry, its traffic lights, its shadow and its PNG encoding — is Core Graphics and ImageIO and is identical on both platforms; the ink is a semantic system colour, and the type that names it is `NSColor` here and `UIColor` on iOS. Keeping only this behind is what lets one implementation draw the artwork for both apps rather than two drifting copies.
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
