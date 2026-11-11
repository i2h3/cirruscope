// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NoteTransferObject` is a value-type snapshot of one note in the connected account's Nextcloud Notes app.
struct NoteTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the note's server-assigned identifier, which is what the route opening it requires.
    let id: Int

    /// `title` is the note's title, which for an ordinary note is its file name without the Markdown extension.
    let title: String

    /// `category` is the folder the note is filed under, or an empty string when it is filed under none.
    let category: String

    /// `isFavorite` is whether the user marked the note a favourite, which is what puts it first in every list of these.
    let isFavorite: Bool

    /// `isReadOnly` is whether the server will refuse edits to the note.
    let isReadOnly: Bool

    /// `modification` is when the note was last changed, which orders these after the favourites.
    let modification: Date
}
