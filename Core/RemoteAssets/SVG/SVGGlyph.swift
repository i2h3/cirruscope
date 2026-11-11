// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGGlyph` is one monochrome vector icon read out of an SVG document: the coordinate system it was drawn in, and the shapes that make up its silhouette.
struct SVGGlyph {
    /// `viewBox` is the rectangle of the coordinate system `shapes` are expressed in.
    let viewBox: CGRect

    /// `shapes` are the icon's painted elements, in the order the document paints them.
    let shapes: [SVGShape]

    init?(data: Data) {
        let parser = SVGDocumentParser()

        guard parser.parse(data) else {
            return nil
        }

        guard let viewBox = parser.viewBox else {
            return nil
        }

        self.viewBox = viewBox
        shapes = parser.accumulated
    }

    /// `shapes(fittedIn:)` are the icon's shapes placed inside `rect`, scaled to fit without distortion, centred on both axes, and flipped onto CoreGraphics' upward y axis.
    ///
    /// The flip is the part worth stating out loud: SVG measures y downward from the top of the viewBox and CoreGraphics measures it upward from the bottom of the context, so a glyph drawn without it comes out mirrored — invisibly so for the many icons that happen to be symmetric, which is what makes getting it wrong easy to miss.
    func shapes(fittedIn rect: CGRect) -> [SVGShape] {
        guard viewBox.width > 0, viewBox.height > 0 else {
            return shapes
        }

        var transform = transform(fittingIn: rect)

        return shapes.compactMap { shape in
            guard let placed = shape.path.copy(using: &transform) else {
                return nil
            }

            return SVGShape(path: placed, fillRule: shape.fillRule)
        }
    }

    /// `transform(fittingIn:)` maps the icon's own coordinates onto `rect`, preserving its aspect ratio and turning SVG's downward y axis into CoreGraphics' upward one.
    func transform(fittingIn rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let originX = rect.minX + (rect.width - viewBox.width * scale) / 2
        let originY = rect.minY + (rect.height - viewBox.height * scale) / 2

        return CGAffineTransform(translationX: originX, y: originY).scaledBy(x: scale, y: -scale).translatedBy(x: -viewBox.minX, y: -viewBox.minY - viewBox.height)
    }
}
