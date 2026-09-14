// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityRowView` is one line of the feed, laid out as the size it is being drawn at requires.
///
/// All three show the same two facts — which file, and which folder it is in — and differ in how much room they have for them. The small card stacks the folder under the filename and stops there. The wider ones add a column for the time. On macOS the medium card is wider still, so the folder moves out of the subtitle into a right-aligned column of its own.
/// What none of them shows is the verb or the actor. The badge on the avatar already states what happened and the face beside it already states who did it, and repeating either in words spends the one line this row has on something it has already said.
struct ActivityRowView: View {
    /// `Layout` is which of the design's row treatments to draw.
    enum Layout {
        /// `compact` stacks the folder under the filename and stops there. The small widget on both platforms, which has room for two lines and no column.
        case compact

        /// `regular` stacks the folder under the filename too, and trails the time in its own column. The iOS medium and both large cards.
        case regular

        /// `columnar` gives the folder a right-aligned column of its own, which only the wider macOS medium card has room for.
        case columnar
    }

    /// `row` is the activity being drawn.
    let row: ActivityRow

    /// `layout` is which treatment to use.
    let layout: Layout

    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `body` draws the row.
    var body: some View {
        HStack(spacing: layout == .compact ? 7 : 9) {
            ActivityAvatarView(row: row, diameter: avatarDiameter, style: style)

            switch layout {
                case .compact:
                    compactText

                case .regular:
                    regularText
                    time

                case .columnar:
                    columnarText
                    folder
                    time
            }
        }
    }

    /// `compactText` is the filename over the folder it sits in.
    ///
    /// The verb, the actor and the time were all here at one point, and each left for the same reason: the line ran off the edge of the card before reaching the end of them, and every one of them was already stated elsewhere in the row. What happened is the badge, and who did it is the face beside it. Where the file lives is the one thing this row alone can say, so it gets the whole of the second line.
    private var compactText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: row.fileName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if !row.directory.isEmpty {
                directory(size: 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `regularText` is the filename over the folder it sits in, which is the same pair the small card shows with more room for it.
    private var regularText: some View {
        VStack(alignment: .leading, spacing: 0) {
            title

            if !row.directory.isEmpty {
                directory(size: 9.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `columnarText` is the verb and filename alone, the folder having a column of its own in this layout.
    private var columnarText: some View {
        title
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `title` is the file this row is about, and nothing else.
    ///
    /// It named the verb too until the widget was seen on a real Home Screen, where the word turned out to be saying what the badge on the avatar beside it had already said. Two statements of the same fact in one row is one too many at this size, and the filename is what somebody is scanning for.
    private var title: some View {
        row.fileText
            .font(.system(size: 11.5))
            .foregroundStyle(style.primaryText)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// `folder` is the right-aligned folder column of the macOS medium card.
    private var folder: some View {
        directory(size: 9)
            .frame(maxWidth: 90, alignment: .trailing)
    }

    /// `directory(size:)` is the folder the file sits in.
    ///
    /// Truncated from the front rather than the middle or the end, because a path that does not fit is one whose leading components are the ones worth dropping — which folder the file is actually in is the last component, and it is what somebody reading this wants.
    private func directory(size: CGFloat) -> some View {
        Text(verbatim: row.directory)
            .font(.system(size: size))
            .foregroundStyle(style.secondaryText)
            .lineLimit(1)
            .truncationMode(.head)
    }

    /// `time` is how long ago the activity happened, narrow enough not to take width from the filename.
    private var time: some View {
        Text(row.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(style.tertiaryText)
            .lineLimit(1)
            .fixedSize()
    }

    /// `avatarDiameter` is the circle size the design gives this layout.
    private var avatarDiameter: CGFloat {
        switch layout {
            case .compact: 21
            case .regular: 23
            case .columnar: 20
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
