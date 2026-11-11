// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of notes is shown in, so that no two of them can disagree about it.
extension Collection<NoteTransferObject> {
    /// `sortedByPriority()` is these notes favourites first, then most recently changed, with the title settling a tie and the identifier settling that.
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
