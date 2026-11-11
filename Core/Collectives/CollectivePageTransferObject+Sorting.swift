// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of collective pages is shown in, so that no two of them can disagree about it.
extension Collection<CollectivePageTransferObject> {
    /// `sortedByModification()` is these pages most recently changed first, with the title settling a tie and the identifier settling that.
    func sortedByModification() -> [CollectivePageTransferObject] {
        sorted { one, other in
            guard one.modification == other.modification else {
                return one.modification > other.modification
            }

            let comparison = one.title.localizedStandardCompare(other.title)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
