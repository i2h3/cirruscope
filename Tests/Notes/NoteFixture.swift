// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation

/// `NoteFixture` is the corpus of notes the note suites run their cases over.
///
/// Shared through a named type rather than copied between suites, for the reason `ServerAppFixture` and `ConversationFixture` are: two suites with their own copies cannot be told apart from two suites that agree.
/// The corpus deliberately contains a favourite, an uncategorized note and a read-only one, because those are the three properties the ordering and the matching actually read.
enum NoteFixture {
    /// `groceries` is an ordinary note, filed under a category, changed most recently of the non-favourites.
    static let groceries = NoteTransferObject(id: 1, title: "Groceries", category: "Home", isFavorite: false, isReadOnly: false, modification: Date(timeIntervalSince1970: 1_700_000_300))

    /// `recipe` is an older note in the same category.
    static let recipe = NoteTransferObject(id: 2, title: "Pancakes", category: "Recipes", isFavorite: false, isReadOnly: false, modification: Date(timeIntervalSince1970: 1_700_000_200))

    /// `pinned` is a favourite, and the oldest of the three — so any list putting it first is putting it there for being a favourite rather than for being recent.
    static let pinned = NoteTransferObject(id: 3, title: "Reading list", category: "", isFavorite: true, isReadOnly: true, modification: Date(timeIntervalSince1970: 1_700_000_100))

    /// `all` is every fixture, in no meaningful order.
    static let all = [recipe, pinned, groceries]
}
