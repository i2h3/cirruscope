// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ConversationEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the account's Talk conversations again.
///
/// Without it the index is only ever written when *this app* decides to write it — on launch and whenever `AccountStore` announces a change — so a Spotlight that has lost or invalidated what it holds has no way to ask for it back, and the results stay missing until the next launch. The conformance is the other direction of that conversation.
///
/// Both requirements answer by donating everything rather than only what was named. `SpotlightIndex` replaces the whole set for a type and deletes what is no longer in it, so a full donation is a superset of any partial one and cannot leave the index disagreeing with the store; a partial path would be a second way of writing the index, with its own bookkeeping to get wrong.
/// It is `ConversationIndexer.shared` that performs it, and that is not indirection for its own sake: the record of what has been donated lives on that indexer's `SpotlightIndex`, so a query building an index of its own would split that bookkeeping in two and leave stale results behind.
///
/// The conformance is gated on the release that introduced the protocol, which is newer than either app's deployment target. Everything else here works unchanged below it — the app simply keeps donating on its own, as it did before, and only loses the system's ability to *ask* for one. The SDK's own line names visionOS as well and this one deliberately does not, following `Widgets.xcconfig`: no target here builds that platform, and a platform nothing builds is a platform that rots.
///
/// Both methods are `nonisolated` although the query itself is main-actor-isolated, and that is forced rather than chosen: `CSSearchableIndexDescription` is not `Sendable`, so a main-actor implementation would be asking the compiler to send one across an isolation boundary. Nothing here reads it, and the `await` onto the indexer is the hop that was going to happen anyway — the same shape `UserNotifier`'s delegate methods use.
@available(macOS 27.0, iOS 27.0, *)
extension ConversationEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the account's Talk conversations again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [String], indexDescription _: CSSearchableIndexDescription) async throws {
        await ConversationIndexer.shared.donateAll()
    }

    /// `reindexAllEntities(indexDescription:)` donates the account's Talk conversations again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await ConversationIndexer.shared.donateAll()
    }
}
