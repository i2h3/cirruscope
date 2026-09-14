// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityHeaderView` is the line every size of the widget opens with: the app's mark, the word `ACTIVITY`, and a marker when the feed is stale.
///
/// The header is what tells somebody at a glance whose widget this is on a Home Screen of widgets, which is why it is present even in the states that have nothing else to show. In those it is drawn in the dimmest colour the design has rather than removed: the widget still has to be identifiable when it is reporting that it has nothing to report.
/// The design puts the app's mark to the left of the wordmark. There is no asset for it: the only marks in the repository are the layers of the Icon Composer bundle, which belong to the app icon, are not reachable from this target, and are a bare cloud rather than the rendered icon the design shows. Adding an image set for it to `Core/Assets.xcassets` is what completes this, and is deliberately left to somebody who can supply the artwork rather than approximated from what happens to be lying around.
struct ActivityHeaderView: View {
    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `isProminent` is whether the wordmark is drawn in the accent colour, which the design reserves for a widget that has something to say.
    var isProminent: Bool = true

    /// `isStale` adds the marker the design gives a feed that could not be refreshed.
    var isStale: Bool = false

    /// `size` is the scale the header is drawn at, which the design grows from 15 points on macOS to 18 on the large card. The wordmark and its tracking are sized from it.
    var size: CGFloat = 16

    /// `body` draws the header.
    var body: some View {
        HStack(spacing: 3) {
            Text("Activity", comment: "The widget's name, used both in the gallery somebody picks widgets from and as the heading above the activity it lists. The heading is drawn in capitals, which the app applies itself, so translate this in sentence case — and as a word rather than a transliteration.")
                .font(.system(size: size * 0.6, weight: .bold))
                .kerning(size * 0.08)
                .foregroundStyle(headingStyle)
                .textCase(.uppercase)

            if isStale {
                Spacer(minLength: 4)

                Text("Stale", comment: "Marks the widget's activity list as older than it should be, because the server could not be reached. Drawn in capitals, which the app applies itself, so translate this in sentence case.")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .kerning(size * 0.08)
                    .foregroundStyle(style.warning)
                    .textCase(.uppercase)
            }
        }
    }

    /// `headingStyle` is the accent for a widget with something to show, the warning colour for a stale one, and the dimmest grey for one with nothing.
    private var headingStyle: AnyShapeStyle {
        if isStale {
            return AnyShapeStyle(style.warning)
        }

        return isProminent ? AnyShapeStyle(style.accent) : style.quaternaryText
    }
}
