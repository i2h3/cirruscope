// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGRenderingState` is what an SVG element inherits from the elements it sits inside: where it is placed, and whether it is painted at all.
struct SVGRenderingState {
    /// `transform` places this element's coordinates in the coordinates of the document's viewBox.
    let transform: CGAffineTransform

    /// `fill` is the fill this element paints with, as written; `"none"` means it paints no interior.
    let fill: String

    /// `stroke` is the stroke this element outlines with, as written, or `nil` if it has none.
    let stroke: String?

    /// `strokeWidth` is the width that stroke is drawn at, in this element's own coordinates.
    let strokeWidth: Double

    /// `fillRule` is the rule deciding which parts of a self-overlapping shape count as inside it, as written; SVG's initial value is `"nonzero"`.
    let fillRule: String

    /// `isFilled` reports whether this element contributes its interior to the silhouette.
    var isFilled: Bool {
        fill != "none"
    }

    /// `isStroked` reports whether this element contributes an outline to the silhouette.
    var isStroked: Bool {
        guard let stroke else {
            return false
        }

        return stroke != "none"
    }

    /// `initial` is the state at the root of a document, which is SVG's own set of initial values: no transform, a black fill, no stroke.
    static let initial = SVGRenderingState(transform: .identity, fill: "black", stroke: nil, strokeWidth: 1, fillRule: "nonzero")

    /// `inheriting(_:)` is the state an element with `attributes` has, given this one as its parent's.
    func inheriting(_ attributes: SVGPresentationAttributes) -> SVGRenderingState {
        var transform = transform

        if let text = attributes.value("transform") {
            transform = SVGTransform.transform(from: text).concatenating(transform)
        }

        return SVGRenderingState(transform: transform, fill: attributes.value("fill") ?? fill, stroke: attributes.value("stroke") ?? stroke, strokeWidth: attributes.number("stroke-width") ?? strokeWidth, fillRule: attributes.value("fill-rule") ?? fillRule)
    }
}
