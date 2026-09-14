// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `ActivityWidgetView` is the whole widget: a header, and whatever the entry says belongs under it.
///
/// It is the one place that knows how a family maps onto the design's cards — how many rows fit, which row treatment they use, and how much the card is padded. Everything below it draws what it is given without asking how big the widget is.
/// The macOS medium card is the one genuine platform difference. It is wider than the iOS one at the same family, which is what buys the folder a column of its own, and that is a `#if os(macOS)` here rather than a second target: the sources are shared and the difference is one line of layout.
struct ActivityWidgetView: View {
    /// `entry` is what to draw.
    let entry: ActivityEntry

    /// `family` is the size being drawn, which decides the layout.
    @Environment(\.widgetFamily)
    private var family

    /// `body` draws the header and the content beneath it.
    var body: some View {
        let style = ActivityStyle()

        VStack(alignment: .leading, spacing: 2) {
            ActivityHeaderView(
                style: style,
                isProminent: entry.content != .empty,
                isStale: entry.isStale,
                size: headerSize
            )

            content(style)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if let footnote = footnote(style) {
                footnote
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(style.cardBackground, for: .widget)
    }

    /// `content(_:)` is whatever the entry says belongs under the header.
    @ViewBuilder
    private func content(_ style: ActivityStyle) -> some View {
        switch entry.content {
            case let .feed(rows):
                VStack(spacing: 0) {
                    ForEach(rows.prefix(rowCount)) { row in
                        ActivityRowView(row: row, layout: rowLayout, style: style)
                            .frame(maxHeight: .infinity)
                    }
                }
                // The design dims a stale feed rather than replacing it, so the rows stay exactly where they were and
                // only their weight changes. Whoever glances at it sees the same list, visibly no longer current.
                .opacity(entry.isStale ? 0.45 : 1)

            case .empty:
                ActivityMessageView(
                    headline: "All quiet",
                    message: "No file changes to show.",
                    style: style
                )

            case .notSignedIn:
                ActivityMessageView(
                    headline: "Not signed in",
                    message: "Open Cirruscope to add your Nextcloud server.",
                    callToAction: "Open Cirruscope",
                    style: style
                )

            case .unavailable:
                ActivityMessageView(
                    headline: "Activity unavailable",
                    message: "This server does not have its activity app switched on.",
                    style: style
                )

            case .redacted:
                ActivityRedactedView(rowCount: rowCount, style: style)
        }
    }

    /// `footnote(_:)` is the dim line at the foot of the card, which only two states have.
    ///
    /// A stale feed says when its rows were last true, because rows with no date on them would simply read as current. An empty one says when the last thing happened, which is what distinguishes a quiet server from one that has never been used.
    private func footnote(_ style: ActivityStyle) -> Text? {
        guard let fetchedAt = entry.fetchedAt else {
            return nil
        }

        guard entry.isStale else {
            return nil
        }

        return Text("Can't reach server · shown \(fetchedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))", comment: "Footnote on the widget when the server could not be reached, so the activity shown is older than it should be. The placeholder is how long ago it was read.")
            .font(.system(size: 8.5))
            .foregroundStyle(style.warning) as Text
    }

    /// `rowCount` is how many rows this size holds, taken from the design's cards.
    private var rowCount: Int {
        switch family {
            case .systemLarge: 10
            case .systemMedium: 4
            default: 3
        }
    }

    /// `rowLayout` is which row treatment this size uses.
    ///
    /// The macOS medium card is wider than the iOS one, which is the whole reason the folder can have a column there and cannot here.
    private var rowLayout: ActivityRowView.Layout {
        switch family {
            case .systemSmall:
                .compact

            case .systemMedium:
                #if os(macOS)
                    .columnar
                #else
                    .regular
                #endif

            default:
                .regular
        }
    }

    /// `headerSize` is the scale the header is drawn at, which the design grows with the card.
    private var headerSize: CGFloat {
        #if os(macOS)
            15
        #else
            family == .systemLarge ? 18 : 16
        #endif
    }
}
