// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of notes is shown in, so that no two of them can disagree about it.
extension Collection<NoteTransferObject> {
    /// `sortedByPriority()` is these notes favourites first, then most recently changed, with the title settling a tie and the identifier settling that.
    ///
    /// Two rules rather than one, and both are the user's own. A favourite is the only thing in this data that is a person saying "this one matters", so it is what a list offering a few notes should offer first; among the rest, the one changed most recently is the one most likely to be meant. Nextcloud's own Notes interface orders them the same way, which matters more here than elsewhere — a list that disagrees with the app it mirrors reads as a bug rather than as a choice.
    /// This is deliberately not the alphabetical rule the server apps use. That rule exists because a menu of apps is a fixed set scanned by name; a note list is not fixed and is not scanned, it is searched — `entities(matching:)` is what answers "where is the one called X", and it answers it by name regardless of this order.
    /// The two fallbacks make the ordering total. `sorted(by:)` promises no stability and the server stamps modification in whole seconds, so ties are ordinary; without them two lists built from the same notes could disagree, which for a donated Spotlight item means the identifier behind a row moving under the user.
    func sortedByPriority() -> [NoteTransferObject] {
        sorted { one, other in
            guard one.isFavorite == other.isFavorite else {
                return one.isFavorite
            }

            guard one.modification == other.modification else {
                return one.modification > other.modification
            }

            let comparison = one.title.localizedStandardCompare(other.title)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
