// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ActivityVerbTests` pins which Nextcloud activity types the widget draws a badge for, and — more importantly — which it refuses.
///
/// The four recognized types are not a guess: they are exactly what the server's own `files` filter admits, `array_intersect(['file_created','file_changed','file_deleted','file_restored'], …)` in the files app's `FileChanges` filter. The refusals matter as much as the matches, because the files app emits `file_downloaded` and `file_favorite_changed` from the same app with the same `file_` prefix, and sharing emits a whole family of types that a looser match would sweep into the wrong badge. A row drawn under a badge that misdescribes it is worse than a row not drawn.
///
struct ActivityVerbTests {
    ///
    /// The four types the server's file filter admits each map to their verb.
    ///
    @Test(arguments: [
        ("file_created", ActivityVerb.created),
        ("file_changed", ActivityVerb.changed),
        ("file_deleted", ActivityVerb.deleted),
        ("file_restored", ActivityVerb.restored),
    ])
    func `A file activity type maps to its verb`(activityType: String, expected: ActivityVerb) {
        #expect(ActivityVerb(activityType: activityType) == expected)
    }

    ///
    /// Other activities of the files app share the `file_` prefix but are not edits, so a prefix match would draw them under an edit badge.
    ///
    @Test(arguments: ["file_downloaded", "file_favorite_changed"])
    func `Another files activity is refused`(activityType: String) {
        #expect(ActivityVerb(activityType: activityType) == nil)
    }

    ///
    /// Sharing activities belong to the `files_sharing` app, which the server's file filter excludes, so none of them may resolve to a verb. `shared_user_self` also ends in a word the naive matcher might read as a verb.
    ///
    @Test(arguments: ["shared", "shared_user_self", "reshared_link_by", "unshared_by", "self_unshared"])
    func `A sharing activity is refused`(activityType: String) {
        #expect(ActivityVerb(activityType: activityType) == nil)
    }

    ///
    /// An activity from another app entirely is refused, calendar events being what a stock instance produces alongside file activity.
    ///
    @Test(arguments: ["calendar_event", "", "file_", "changed"])
    func `An unrelated activity type is refused`(activityType: String) {
        #expect(ActivityVerb(activityType: activityType) == nil)
    }
}
