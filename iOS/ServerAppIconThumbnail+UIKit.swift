// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import UIKit

/// This extension resolves the colour iOS fills a donated app glyph with.
extension ServerAppIconThumbnail {
    /// `glyphColor()` is the colour the app's glyph is filled with: the secondary label colour, resolved in the light appearance.
    static func glyphColor() -> CGColor? {
        UIColor.secondaryLabel.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
    }
}
