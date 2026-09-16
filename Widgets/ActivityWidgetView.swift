// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `ActivityWidgetView` is the whole widget: a header, and whatever the entry says belongs under it.
///
/// It is the one place that knows how a family maps onto the design's cards — how many rows fit, which scale they are drawn at, and which of them trail the time. Everything below it draws what it is given without asking how big the widget is.
/// The rows deliberately do not differ by platform. A Mac's medium card is wider than a phone's but no taller, so it holds the same three rows drawn the same way.
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
                // Bounded because the feed pays for every line of it. The sentence wraps to two on a small card in
                // German, and a translation long enough to want a third would be taking it out of the rows.
                footnote
                    .lineLimit(2)
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
                    ForEach(0 ..< rowCount, id: \.self) { index in
                        feedRow(rows, at: index, style: style)
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

    /// `feedRow(_:at:style:)` is the row belonging to one of the card's slots, or the empty space where a shorter feed has none.
    ///
    /// A card draws the full number of slots its size holds whether or not there are rows for all of them, and the slots divide the feed's height equally between them. Two rows on a card built for three therefore sit where the first two of a full card sit — at the top, the same distance apart as always — rather than sharing the whole height between them and drifting towards the middle as the feed shrinks. It is also the shape the redacted card draws, so nothing moves when real rows replace the bars.
    @ViewBuilder
    private func feedRow(_ rows: [ActivityRow], at index: Int, style: ActivityStyle) -> some View {
        if index < rows.count {
            ActivityRowView(row: rows[index], layout: rowLayout, showsTime: showsTime, style: style)
        } else {
            Color.clear
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
    ///
    /// The medium card holds what the small one does. It is wider, which buys the time a column of its own, but it is exactly as tall, and height is what a row costs.
    private var rowCount: Int {
        family == .systemLarge ? 10 : 3
    }

    /// `rowLayout` is the scale this size draws its rows at.
    ///
    /// Only the large card has the height to spare for the larger setting. The other two are the same card at different widths and are drawn the same way.
    private var rowLayout: ActivityRowView.Layout {
        family == .systemLarge ? .regular : .compact
    }

    /// `showsTime` is whether a row trails how long ago it happened, which is a matter of width rather than of height.
    ///
    /// The small card is about half a line wide, and the time there would be taken out of the filename. Every larger card has the room.
    private var showsTime: Bool {
        family != .systemSmall
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
