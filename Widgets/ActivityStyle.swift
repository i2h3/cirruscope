// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityStyle` is every colour the activity widget draws with, in one place so that no view decides for itself what "secondary text" or "the badge ring" means.
///
/// Nothing here is a literal. The two colours the app owns are the assets already shipped in `Core/Assets.xcassets`, and every other one is the system's own. That is worth more than matching a mockup exactly: a system colour follows the appearance, Increase Contrast, and the accented and vibrant widget rendering modes on its own, where a transcribed hex value is correct in one of those and wrong in the rest.
/// It is also why this takes no `ColorScheme`. Every value below resolves itself against the environment it is drawn in, so there is one style rather than a light one and a dark one, and nothing upstream has to know which is being drawn.
struct ActivityStyle {
    /// `accent` is the cobalt the heading and the changed badge are drawn in: the app's own accent colour, which already carries its light and dark values.
    let accent = Color("AccentColor", bundle: .main)

    /// `cardBackground` is the widget's own surface, which the badge ring is drawn in so the ring reads as a cut-out rather than as an outline in some colour of its own.
    let cardBackground = Color("WidgetBackground", bundle: .main)

    /// `primaryText` is the filename and everything else meant to be read first.
    let primaryText = AnyShapeStyle(HierarchicalShapeStyle.primary)

    /// `secondaryText` is the subtitle beneath it, which is the folder.
    let secondaryText = AnyShapeStyle(HierarchicalShapeStyle.secondary)

    /// `tertiaryText` is the relative time, the least of the three and never what somebody is scanning for.
    let tertiaryText = AnyShapeStyle(HierarchicalShapeStyle.tertiary)

    /// `quaternaryText` is the dimmest, for the heading of a widget with nothing to report and the footnote under it.
    let quaternaryText = AnyShapeStyle(HierarchicalShapeStyle.quaternary)

    /// `placeholderStrong` is the fill of the wider bar in a redacted row.
    let placeholderStrong = AnyShapeStyle(HierarchicalShapeStyle.quaternary)

    /// `placeholderWeak` is the fill of the narrower bar beneath it.
    let placeholderWeak = AnyShapeStyle(HierarchicalShapeStyle.quinary)

    /// `warning` marks a stale widget, and badges a restoration.
    let warning = Color.orange

    /// `created` badges a creation.
    let created = Color.green

    /// `deleted` badges a deletion.
    let deleted = Color.red

    /// `avatarFills` are the colours an actor's circle is filled with, chosen per actor so two people in one feed are told apart at a glance.
    ///
    /// Green, red and orange are deliberately absent. They mean something specific on this card — they are the three badges — and a badge sits on the corner of one of these circles, so a green disc under a green badge would read as one shape rather than two.
    let avatarFills: [Color] = [.blue, .purple, .teal, .pink, .indigo, .brown, .mint]

    /// `badgeColor(for:)` is the colour one verb's badge is filled with.
    ///
    /// The amber was the share badge's in the design. Sharing is out of the widget's scope — the server publishes no filter covering file changes and shares together, which `DECISIONS.md` records — so restoring takes the slot rather than the palette losing a colour.
    func badgeColor(for verb: ActivityVerb) -> Color {
        switch verb {
            case .created: created
            case .changed: accent
            case .deleted: deleted
            case .restored: warning
        }
    }

    /// `avatarFill(for:)` is the circle colour one actor is always drawn with.
    ///
    /// It is chosen by hashing the name rather than by the row's position, so a person keeps their colour as the feed moves under them. `String.hashValue` is deliberately not used: it is seeded per process, which would repaint every circle on each launch.
    func avatarFill(for name: String) -> Color {
        var hash: UInt64 = 5381

        for byte in name.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }

        return avatarFills[Int(hash % UInt64(avatarFills.count))]
    }
}
