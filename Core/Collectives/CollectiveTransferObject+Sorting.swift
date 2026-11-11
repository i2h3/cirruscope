// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of collectives is shown in, so that no two of them can disagree about it.
extension Collection<CollectiveTransferObject> {
    /// `sortedByName()` is these collectives alphabetically by name, with the identifier settling a tie.
    func sortedByName() -> [CollectiveTransferObject] {
        sorted { one, other in
            let comparison = one.name.localizedStandardCompare(other.name)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
