// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `ServerNote` is the v3 record for a note's metadata exactly as it shipped in `1.2.0` and `1.2.1`.
    ///
    /// It is a frozen copy; see `SchemaV3` for why it never changes.
    @Model
    final class ServerNote {
        /// `noteID` is the note's server-assigned identifier, which is what the route opening it requires.
        ///
        /// Not named `id`, because SwiftData treats that name as the model's own identity and this is the server's.
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
}
