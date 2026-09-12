// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ActivityVerb` is what a Nextcloud file activity did, reduced to the four outcomes a widget row can draw a badge for.
///
/// Nextcloud names an activity by a type string rather than by a verb, and the files app alone registers more of them than a badge could distinguish — downloads and favourite changes among them. This maps the ones the server's own `files` filter admits, which is exactly `file_created`, `file_changed`, `file_deleted` and `file_restored`, and answers `nil` for anything else so an unrecognized type is dropped rather than drawn under a badge that would misdescribe it.
/// Sharing activities are deliberately absent. They belong to the `files_sharing` app, and the server offers no filter covering file changes and shares together — see `DECISIONS.md`. Should that scope ever widen, a `shared` case belongs here beside these four rather than at the view.
enum ActivityVerb: String, CaseIterable, Sendable {
    /// `created` is a file or folder appearing, which the server reports as `file_created`.
    case created

    /// `changed` is a file's contents being written, which the server reports as `file_changed`.
    case changed

    /// `deleted` is a file or folder being removed, which the server reports as `file_deleted`.
    case deleted

    /// `restored` is a file returning from the trash, which the server reports as `file_restored`.
    case restored

    /// `init(activityType:)` recognizes one of the four file activity types the server's `files` filter admits, and answers `nil` for every other type.
    ///
    /// The comparison is against the server's own literals rather than a prefix or a suffix, because the files app also emits `file_downloaded` and `file_favorite_changed`, both of which a prefix match on `file_` would sweep up and a suffix match on `_changed` would confuse with an edit.
    init?(activityType: String) {
        switch activityType {
            case "file_created":
                self = .created

            case "file_changed":
                self = .changed

            case "file_deleted":
                self = .deleted

            case "file_restored":
                self = .restored

            default:
                return nil
        }
    }
}
