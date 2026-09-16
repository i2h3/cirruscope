// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Rainmaker

/// `ActivityRow` is one line of the activity widget, reduced to exactly what a layout draws and nothing else.
///
/// A Nextcloud activity arrives as a rendered sentence plus the parts it was rendered from, and the widget needs the parts: the filename carries the weight in every size, the verb picks the badge, the actor draws the circle beside it, and the folder fills the line underneath. Doing that once here rather than in each layout is what keeps the three families from each deriving the same values slightly differently.
/// The verb is taken from `ActivityItem.type` rather than from the server's sentence, so it can be localized into the language the device is set to. `subjectRich`'s template is localized into the language the *Nextcloud account* is set to, which is not necessarily the same one, and a widget whose empty state reads "Nichts Neues" should not describe its rows in English.
struct ActivityRow: Identifiable, Hashable, Codable, Sendable {
    /// `id` is the server's own activity identifier, which is unique per instance and stable across refreshes, so SwiftUI keeps a row's identity when the feed shifts under it.
    let id: Int

    /// `verb` is what happened, and picks the glyph on the badge, which is the only place a row states it — `DECISIONS.md` records why no size writes the word out.
    let verb: ActivityVerb

    /// `fileName` is the last component of the affected path, which is the one thing every size shows and the small size shows alone.
    let fileName: String

    /// `directory` is the folder the file sits in, shown in the subtitle beside the actor, and empty for a file at the account's root.
    let directory: String

    /// `actorID` is the login name of whoever acted, or `nil` when that was the signed-in user.
    ///
    /// This is what an avatar is fetched and cached by, the endpoint keying on the login name rather than on the display name — two people may share the latter, and one person may change it.
    let actorID: String?

    /// `actorName` is the display name of whoever acted, or `nil` when that was the signed-in user.
    ///
    /// The server omits the actor entirely for your own activities — the template reads `You changed {file}` with no `actor` parameter to resolve — so `nil` is the server's answer rather than a failure to read one. No layout writes a name for it: the avatar draws a figure in place of initials, which is the whole of how a row of your own is marked.
    let actorName: String?

    /// `additionalCount` is how many further files the server merged into this one activity, and zero when it merged none.
    ///
    /// Nextcloud collapses a burst of activity on one folder into a single entry listing every object, which is what the design's "and 11 more" reports.
    let additionalCount: Int

    /// `date` is when the activity happened, which every size renders as a short relative time.
    let date: Date

    /// `initials` is the monogram drawn in the avatar circle until a profile photo is available, and empty for your own activities, which show no circle content of their own.
    var initials: String {
        ActivityRow.initials(forDisplayName: actorName)
    }
}

extension ActivityRow {
    /// `init(_:)` prepares one server activity for drawing, or answers `nil` when it is not one the widget can draw.
    ///
    /// An activity is refused when its type is not one of the four the badges cover, or when it names no file. Refusing here rather than rendering a partial row is what keeps an unexpected activity type from appearing as a blank line with a badge that means something else.
    init?(_ item: ActivityItem) {
        guard let verb = ActivityVerb(activityType: item.type) else {
            return nil
        }

        let file = item.subjectRich?.parameters.values.first { $0.type == "file" }

        guard let fileName = file?.name ?? ActivityRow.lastComponent(ofPath: item.objectName) else {
            return nil
        }

        // Absent for your own activities, which the server renders as "You" and gives no actor to resolve.
        let actor = item.subjectRich?.parameters.values.first { $0.type == "user" }

        self.init(
            id: item.id,
            verb: verb,
            fileName: fileName,
            directory: ActivityRow.directory(ofPath: file?.path ?? item.objectName),
            actorID: actor?.id,
            actorName: actor?.name,
            additionalCount: max(0, item.objects.count - 1),
            date: item.creation
        )
    }

    /// `directory(ofPath:)` is the folder part of a path the server named, without a leading or trailing separator, and empty when the file sits at the account's root.
    ///
    /// The server spells this path relative to the account's own root and without a leading slash in the rich parameter — `Documents/Planning/Q3 Roadmap.md` — but spells the same file with one in `objectName`, so both are accepted and neither leaks a stray separator into the subtitle.
    static func directory(ofPath path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)

        guard components.count > 1 else {
            return ""
        }

        return components.dropLast().joined(separator: "/")
    }

    /// `lastComponent(ofPath:)` is the filename a path ends in, or `nil` when the path names nothing.
    static func lastComponent(ofPath path: String) -> String? {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
    }

    /// `initials(forDisplayName:)` is the monogram for an actor's circle: the first letter of the first and last words of their display name, or just the first when there is only one word.
    ///
    /// It answers an empty string for your own activities, which carry no actor at all, and for a name that is nothing but separators. Letters are taken by `Character` rather than by `UnicodeScalar` so a grapheme cluster stays whole, which matters for the scripts where an initial is more than one scalar.
    static func initials(forDisplayName displayName: String?) -> String {
        guard let displayName else {
            return ""
        }

        let words = displayName.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }

        guard let first = words.first?.first else {
            return ""
        }

        guard words.count > 1, let last = words.last?.first else {
            return String(first).uppercased()
        }

        return (String(first) + String(last)).uppercased()
    }
}
