// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `ActivityWidget` shows what has been happening to the files on the connected Nextcloud server.
///
/// One idea per widget: the newest file activity, newest first, and nothing else. Scope is the server's own file filter, which admits creations, changes, deletions and restorations and excludes sharing — `DECISIONS.md` records why the widget shows no shares.
/// It takes no configuration. There is one connected account and one thing to show about it, so there is nothing to ask, and an intent configuration would put a settings sheet on a widget whose only setting would be which of one account to use.
/// Tapping it opens Cirruscope, which is what a widget with no link of its own does by default. Nothing here declares one: the rows are a summary rather than a set of destinations, and every one of them would open the same window.
struct ActivityWidget: Widget {
    /// `kind` is the identifier WidgetKit tells this widget's configured instances apart by.
    ///
    /// It must stay stable for as long as the widget exists — instances already placed on a Home Screen are keyed by it, and changing it would orphan them.
    static let kind = "ActivityWidget"

    /// `body` declares the widget and the sizes it offers.
    ///
    /// The three system families are the ones the design draws. The accessory families are deliberately absent: they exist only on iOS, hold a fraction of a line, and the design says nothing about what this widget would be reduced to at that size.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ActivityTimelineProvider()) { entry in
            ActivityWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Activity", comment: "The widget's name, used both in the gallery somebody picks widgets from and as the heading above the activity it lists. The heading is drawn in capitals, which the app applies itself, so translate this in sentence case — and as a word rather than a transliteration."))
        .description(Text("Recent changes to the files on your Nextcloud server.", comment: "The widget's description in the gallery somebody picks widgets from."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

// These render in Xcode's canvas only with an iOS Simulator destination selected. The macro compiles on macOS — its
// availability is `macOS 14.0` — but no macOS widget host exists for the canvas to run the extension in, which is the
// reason the iOS app target exists at all; see `DECISIONS.md`. Do not reach for `WidgetPreviewContext` alongside these:
// combining the two emits "previewContext is ignored in a #Preview macro" and the context is silently dropped.
//
// Each timeline carries a one-row feed as well as a full one. A card divides its height into a fixed number of slots
// whether or not there are rows for all of them, and the single row is what shows that: it has to sit at the top,
// where the first row of a full card sits, rather than in the middle of the space it has to itself.

#Preview("Small", as: .systemSmall) {
    ActivityWidget()
} timeline: {
    ActivityEntry(date: .now, content: .empty, fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .redacted)
    ActivityEntry(date: .now, content: .notSignedIn)
    ActivityEntry(date: .now, content: .unavailable)
}

#Preview("Medium", as: .systemMedium) {
    ActivityWidget()
} timeline: {
    ActivityEntry(date: .now, content: .empty, fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .redacted)
    ActivityEntry(date: .now, content: .notSignedIn)
    ActivityEntry(date: .now, content: .unavailable)
}

#Preview("Large", as: .systemLarge) {
    ActivityWidget()
} timeline: {
    ActivityEntry(date: .now, content: .empty, fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(ActivityRow.previewRows), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now)
    ActivityEntry(date: .now, content: .feed(Array(ActivityRow.previewRows.prefix(1))), fetchedAt: .now.addingTimeInterval(-7200), isStale: true)
    ActivityEntry(date: .now, content: .redacted)
    ActivityEntry(date: .now, content: .notSignedIn)
    ActivityEntry(date: .now, content: .unavailable)
}

extension ActivityRow {
    /// `previewRows` is the sample feed the previews draw, matching the design's own cards so a preview and the mockup can be compared side by side.
    ///
    /// One row deliberately has no actor, which is how the server reports your own activity and the only way to see the figure the avatar draws in place of initials. Another is named `_draft_.md` and sits at the account's root, so it covers two cases at once: a legal filename that is also markdown emphasis, and a row with no folder to put under it. It is there as a regression guard: the underscores must survive, and they only do because `ActivityRow.fileText` hands the name over as a `Text` rather than interpolating it into a `LocalizedStringKey`, which would parse it.
    static var previewRows: [ActivityRow] {
        [
            ActivityRow(id: 1, verb: .changed, fileName: "Q3 Roadmap.md", directory: "Documents/Planning", actorID: "anja", actorName: "Anja Kranz", additionalCount: 0, date: .now.addingTimeInterval(-240)),
            ActivityRow(id: 2, verb: .created, fileName: "Release Notes 31.md", directory: "Documents/Releases", actorID: "marcel", actorName: "Marcel Durand", additionalCount: 0, date: .now.addingTimeInterval(-720)),
            ActivityRow(id: 3, verb: .deleted, fileName: "old-mockup-v2.png", directory: "Design/Archive", actorID: "lena", actorName: "Lena Hoff", additionalCount: 0, date: .now.addingTimeInterval(-2460)),
            ActivityRow(id: 4, verb: .restored, fileName: "budget-2026.ods", directory: "Finance/2026", actorID: "tomas", actorName: "Tomás Rivas", additionalCount: 0, date: .now.addingTimeInterval(-3600)),
            ActivityRow(id: 5, verb: .changed, fileName: "contract-final.pdf", directory: "Legal", actorID: nil, actorName: nil, additionalCount: 0, date: .now.addingTimeInterval(-5400)),
            ActivityRow(id: 6, verb: .created, fileName: "DSC_0421.jpg", directory: "Photos/Trip", actorID: "ilse", actorName: "Ilse Brandt", additionalCount: 11, date: .now.addingTimeInterval(-7200)),
            ActivityRow(id: 7, verb: .changed, fileName: "Design Review.pdf", directory: "Design", actorID: "jos", actorName: "Jos Meijer", additionalCount: 0, date: .now.addingTimeInterval(-86400)),
            ActivityRow(id: 8, verb: .created, fileName: "brand-assets.zip", directory: "Marketing", actorID: "lena", actorName: "Lena Hoff", additionalCount: 0, date: .now.addingTimeInterval(-90000)),
            ActivityRow(id: 9, verb: .deleted, fileName: "invoice-draft.ods", directory: "Finance/2026", actorID: "tomas", actorName: "Tomás Rivas", additionalCount: 0, date: .now.addingTimeInterval(-172_800)),
            ActivityRow(id: 10, verb: .restored, fileName: "_draft_.md", directory: "", actorID: "anja", actorName: "Anja Kranz", additionalCount: 0, date: .now.addingTimeInterval(-259_200)),
        ]
    }
}
