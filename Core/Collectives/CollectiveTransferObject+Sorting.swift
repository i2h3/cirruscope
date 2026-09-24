// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of collectives is shown in, so that no two of them can disagree about it.
extension Collection<CollectiveTransferObject> {
    /// `sortedByName()` is these collectives alphabetically by name, with the identifier settling a tie.
    ///
    /// Alphabetical, where a conversation list is ordered by activity and a note list by what the user pinned. That is the rule rather than an exception to it: the order follows what the list is *for*, and a collective is a container with a name somebody chose — the same kind of thing as a server app, scanned for a name rather than read for what is new. The server returns them unsorted, so something has to impose an order regardless.
    /// `localizedStandardCompare(_:)` rather than `<`, for the reason `ServerAppTransferObject`'s own sorting documents: `<` orders by Unicode scalar, which files every lowercase name behind every uppercase one and reads "Team 10" as preceding "Team 2". The identifier fallback makes the ordering total, since `sorted(by:)` promises no stability and two collectives may share a name.
    func sortedByName() -> [CollectiveTransferObject] {
        sorted { one, other in
            let comparison = one.name.localizedStandardCompare(other.name)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
