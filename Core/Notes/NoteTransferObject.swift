// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NoteTransferObject` is a value-type snapshot of one note in the connected account's Nextcloud Notes app.
///
/// It is the shape both apps pass around and the shape `AccountStore` is written with and read from, so nothing about the store's surface depends on the network library's own models — the same arrangement `ServerAppTransferObject` and `ConversationTransferObject` have, and what lets a test seed notes without either test target linking Rainmaker.
///
/// **It carries no note text, and that is the point of the type.** The server sends every note's full Markdown body, and this drops it at the boundary rather than a layer later: the store is an unencrypted file in a shared App Group container, and a person's notes are the most private thing this app could put there. What the feature needs is a way to find a note and open it, and a title and a category are enough for both — the body is fetched by the web view from the server when the note is actually opened, over the connection that was already going to carry it.
/// The apparent middle ground, of indexing the body into Spotlight without storing it here, is not one: Spotlight's index is itself a file on disk and no more encrypted than this store. That is a separate decision to make deliberately rather than to arrive at by accident, and it is recorded as declined in `DECISIONS.md`.
struct NoteTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the note's server-assigned identifier, which is what the route opening it requires.
    ///
    /// A number rather than a slug or a file name: the Notes app's own page route matches `\d+` and nothing else, so this is the only thing that addresses a note.
    let id: Int

    /// `title` is the note's title, which for an ordinary note is its file name without the Markdown extension.
    let title: String

    /// `category` is the folder the note is filed under, or an empty string when it is filed under none.
    ///
    /// Empty rather than `nil` because that is what the server sends, and the distinction it would carry does not exist: a note is either in a category or at the top level, and there is no third state for `nil` to mean.
    let category: String

    /// `isFavorite` is whether the user marked the note a favourite, which is what puts it first in every list of these.
    let isFavorite: Bool

    /// `isReadOnly` is whether the server will refuse edits to the note.
    let isReadOnly: Bool

    /// `modification` is when the note was last changed, which orders these after the favourites.
    let modification: Date
}
