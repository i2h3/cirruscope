// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityRowView` is one line of the feed, laid out as the size it is being drawn at requires.
///
/// Every size shows the same two facts, stacked one over the other — which file, and which folder it is in — and they differ only in how much room they have for them. The small card stops at that pair. The medium card is the same row again on a wider card, with the time trailing it. The large card has the height to set all of it a little larger.
/// What none of them shows is the verb or the actor. The badge on the avatar already states what happened and the face beside it already states who did it, and repeating either in words spends the one line this row has on something it has already said.
struct ActivityRowView: View {
    /// `Layout` is the scale the design draws a row at.
    enum Layout {
        /// `compact` is the small and medium cards, which are the same height as each other and have room for two lines of small type.
        case compact

        /// `regular` is the large card, which has the height to set the same two lines a little larger.
        case regular
    }

    /// `row` is the activity being drawn.
    let row: ActivityRow

    /// `layout` is the scale to draw at.
    let layout: Layout

    /// `showsTime` trails how long ago the activity happened, which every card but the small one has the width for.
    let showsTime: Bool

    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `body` draws the row.
    var body: some View {
        HStack(spacing: layout == .compact ? 7 : 9) {
            ActivityAvatarView(row: row, diameter: avatarDiameter, style: style)

            VStack(alignment: .leading, spacing: 0) {
                row.fileText
                    .font(.system(size: layout == .compact ? 10.5 : 11.5))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !row.directory.isEmpty {
                    // Truncated from the front rather than the middle or the end, because a path that does not fit is
                    // one whose leading components are the ones worth dropping — which folder the file is actually in
                    // is the last component, and it is what somebody reading this wants.
                    Text(verbatim: row.directory)
                        .font(.system(size: layout == .compact ? 9 : 9.5))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsTime {
                Text(row.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // One row is one thing to hear, in the order it is drawn: who did what, to which file, in which folder, when.
        // Combining rather than relabelling is what keeps the merged "and 11 more" and the folder in it without this
        // view restating either.
        .accessibilityElement(children: .combine)
    }

    /// `avatarDiameter` is the circle size the design gives this scale.
    private var avatarDiameter: CGFloat {
        switch layout {
            case .compact: 21
            case .regular: 23
        }
    }
}

extension ActivityRow {
    /// `fileText` is the file an activity is about: its name, emphasized, and however many further files the server merged in with it.
    ///
    /// The name is a `Text` rather than a value interpolated into one, and that is load-bearing. A `LocalizedStringKey` is parsed as markdown, and so is anything interpolated into it — a file legitimately named `_draft_.md` comes back out of that as `draft.md`, silently, because the underscores were read as emphasis. Interpolating a `Text` inserts it as it is instead, which is what makes the emphasis safe to apply here rather than with a pair of asterisks around a placeholder in the catalog.
    var fileText: Text {
        let name = Text(verbatim: fileName).bold()

        guard additionalCount > 0 else {
            return name
        }

        return Text("\(name) and \(additionalCount) more", comment: "Names a file together with how many further files the server merged into the same activity, in the widget. The first placeholder is the file's name, emphasized; the second is how many further files there were.")
    }
}
