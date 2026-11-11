// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of Talk conversations is shown in, so that no two of them can disagree about it.
extension Collection<ConversationTransferObject> {
    /// `sortedByActivity()` is these conversations most recently active first, with the display name settling a tie and the token settling that.
    func sortedByActivity() -> [ConversationTransferObject] {
        sorted { one, other in
            guard one.lastActivity == other.lastActivity else {
                return one.lastActivity > other.lastActivity
            }

            let comparison = one.name.localizedStandardCompare(other.name)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
