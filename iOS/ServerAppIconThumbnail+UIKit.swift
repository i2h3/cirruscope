// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import os
import UIKit

/// This extension resolves the colour iOS fills a donated app glyph with.
///
/// It is the counterpart of the AppKit file of the same name, and the only part of the artwork that differs between the two platforms: the ink is a semantic system colour, named by `UIColor` here and by `NSColor` there, while the plate, the traffic lights, the shadow and the PNG encoding are Core Graphics and ImageIO and are shared.
extension ServerAppIconThumbnail {
    /// `glyphColor()` is the colour the app's glyph is filled with: the secondary label colour, resolved in the light appearance.
    ///
    /// The light one always, and deliberately, for the same reason the Mac resolves it that way: the plate is white whatever the system is set to, so the ink on it has to be the one meant for a light surface. Resolving it in the current appearance would produce pale grey on white the moment the user switched to dark — and Spotlight draws these bytes literally rather than tinting them, so nothing downstream would correct it.
    /// `resolvedColor(with:)` rather than a drawing-appearance block, that being how UIKit answers the same question: a dynamic colour is resolved against a trait collection rather than against an appearance made current.
    static func glyphColor() -> CGColor? {
        UIColor.secondaryLabel.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
    }
}
