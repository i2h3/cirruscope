// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of collective pages is shown in, so that no two of them can disagree about it.
extension Collection<CollectivePageTransferObject> {
    /// `sortedByModification()` is these pages most recently changed first, with the title settling a tie and the identifier settling that.
    ///
    /// By recency where the collectives containing them are alphabetical, and the two together are the rule rather than an inconsistency: the order follows what the list is for. A collective is a container somebody named, scanned for that name; a page is a document, and the question asked of a list of documents offered without being searched for is which one was being worked on. That is the same answer notes get, for the same reason.
    /// The two fallbacks make the ordering total. The server stamps modification in whole seconds and `sorted(by:)` promises no stability, so without them the identifier behind a donated Spotlight row could move between one refresh and the next.
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
