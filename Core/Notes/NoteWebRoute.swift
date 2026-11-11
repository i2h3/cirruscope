// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NoteWebRoute` is where a note lives in the web interface.
enum NoteWebRoute {
    /// `appID` is the identifier of the Nextcloud app that owns a note, which is what its icon is cached under.
    static let appID = "notes"

    /// `url(forID:on:)` is the address of the note `id` names on `serverAddress`, or `nil` when there is no address to be confident in.
    static func url(forID id: Int, on serverAddress: URL) -> SameOriginURL? {
        guard id >= 0 else {
            return nil
        }

        return SameOriginURL(components: ["apps", "notes", "note", String(id)], relativeTo: serverAddress)
    }
}
