// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of server apps is shown in, so that no two of them can disagree about it.
extension Collection<ServerAppTransferObject> {
    /// `sortedByName()` is these apps alphabetically by localized name, with the app identifier settling a tie.
    func sortedByName() -> [ServerAppTransferObject] {
        sorted { one, other in
            let comparison = one.name.localizedStandardCompare(other.name)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
