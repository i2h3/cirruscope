// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ActivityVerb` is what a Nextcloud file activity did, reduced to the four outcomes a widget row can draw a badge for.
enum ActivityVerb: String, CaseIterable, Codable, Sendable {
    /// `created` is a file or folder appearing, which the server reports as `file_created`.
    case created

    /// `changed` is a file's contents being written, which the server reports as `file_changed`.
    case changed

    /// `deleted` is a file or folder being removed, which the server reports as `file_deleted`.
    case deleted

    /// `restored` is a file returning from the trash, which the server reports as `file_restored`.
    case restored

    /// `init(activityType:)` recognizes one of the four file activity types the server's `files` filter admits, and answers `nil` for every other type.
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
