// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of Talk conversations is shown in, so that no two of them can disagree about it.
extension Collection<ConversationTransferObject> {
    /// `sortedByActivity()` is these conversations most recently active first, with the display name settling a tie and the token settling that.
    ///
    /// Not alphabetical, and that is a deliberate departure from how the server apps are listed. An app list is a menu of fixed things a person scans by name, which is why it is sorted the way Finder sorts names; a conversation list is a record of what has been happening, and the question asked of it is "what is new", not "where is the one called X". Nextcloud's own Talk interface lists them this way, and Rainmaker's documentation says outright that the server does not sort them and expects a client to sort by last activity descending.
    /// The two fallbacks exist to make the ordering total. `sorted(by:)` promises no stability, so two conversations sharing a timestamp — which the server produces readily, since it stamps whole seconds — would otherwise be free to swap places between one list and the next.
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
