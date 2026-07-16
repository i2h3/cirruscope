// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `StateOverlayStackView` is the vertical `NSStackView` `WebViewController` shows over the themed backdrop while a page loads or after a load fails, styled as a plain rounded card.
///
/// It draws a filled `controlBackgroundColor` background with rounded corners and insets its arranged views by 16 points on every edge. The fill is applied in `updateLayer()` rather than once at setup so it re-resolves whenever the effective appearance changes — a raw `CGColor` set on the layer would otherwise keep the light- or dark-mode color it was first given. `WebViewController` toggles the visibility of the progress indicator, headline, explanation, and retry button it contains.
class StateOverlayStackView: NSStackView {
    /// Interior padding, in points, between the card's edges and its content.
    private let padding: CGFloat = 16

    override func awakeFromNib() {
        super.awakeFromNib()

        wantsLayer = true
        layer?.cornerRadius = padding

        // `edgeInsets` pads the vertical stacking axis, which NSStackView honors. It does not pad the
        // horizontal (cross) axis: the widest arranged view — the explanation label — overflows it and
        // sits flush against the card edges. So the horizontal padding is enforced explicitly by pinning
        // each arranged view's leading and trailing inside the stack, which the vertical `edgeInsets`
        // still handles the top and bottom of.
        edgeInsets = NSEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)

        for view in arrangedSubviews {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: padding),
                trailingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor, constant: padding),
            ])
        }
    }

    /// Opt into `updateLayer()`-based drawing so the background color is set with the effective appearance current, keeping it correct in both light and dark mode.
    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
