// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `ServerNote` is the SwiftData record for one note in the connected account's Nextcloud Notes app, persisted so Spotlight and the Shortcuts app can be offered them without the server having been asked first.
///
/// **There is no field for the note's text, and its absence is the design rather than an omission.** The store is unencrypted and lives in a container an app extension can also open; a person's notes are the most private thing this app has any reason to touch. The refresh never downloads the body, so nothing downstream ever holds it, and the web view fetches it from the server when a note is actually opened.
@Model
final class ServerNote {
    /// `noteID` is the note's server-assigned identifier, which is what the route opening it requires.
    var noteID: Int

    /// `title` is the note's title, which for an ordinary note is its file name without the Markdown extension.
    var title: String

    /// `category` is the folder the note is filed under, or an empty string when it is filed under none.
    var category: String

    /// `isFavorite` is whether the user marked the note a favourite, which is what puts it first in every list of these.
    var isFavorite: Bool

    /// `isReadOnly` is whether the server will refuse edits to the note.
    var isReadOnly: Bool

    /// `modification` is when the note was last changed, which orders these after the favourites.
    var modification: Date

    /// `account` is the account this note belongs to; it is the inverse of `Account.notes`.
    var account: Account?

    init(noteID: Int, title: String, category: String, isFavorite: Bool, isReadOnly: Bool, modification: Date, account: Account? = nil) {
        self.noteID = noteID
        self.title = title
        self.category = category
        self.isFavorite = isFavorite
        self.isReadOnly = isReadOnly
        self.modification = modification
        self.account = account
    }
}
