// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `StateOverlayStackView` is the vertical `NSStackView` `WebViewController` shows over the themed backdrop while a page loads or after a load fails, styled as a plain rounded card.
class StateOverlayStackView: NSStackView {
    /// Interior padding, in points, between the card's edges and its content.
    private let padding: CGFloat = 16

    /// `drawsBackground` is `false` while the card should stay transparent so the host window's material shows through it instead of an opaque fill.
    var drawsBackground = true {
        didSet {
            needsDisplay = true
        }
    }

    /// `awakeFromNib()` rounds the card's corners and establishes the padding around its arranged views once the storyboard has finished loading it.
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
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
    }

    /// Opt into `updateLayer()`-based drawing so the background color is set with the effective appearance current, keeping it correct in both light and dark mode.
    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = drawsBackground ? NSColor.controlBackgroundColor.cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
