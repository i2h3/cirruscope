// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s Talk conversations: fetching what the server lists and recording it.
///
/// It is the sibling of `refreshNavigationApps(using:)` and has the same shape deliberately — fetch, map the network library's model to this app's own value type, hand that to the store — because the mapping is the whole reason this lives outside `AccountStore`. Neither test target links Rainmaker, so a store whose writer took a `Rainmaker.Conversation` could not be exercised at all; keeping the boundary here is what lets a suite seed conversations from plain values.
extension ServerConnection {
    /// `refreshConversations(using:)` fetches the Talk conversations the authenticated `server` lists and persists them, or clears what was stored when the server has no Talk app.
    ///
    /// Availability is decided from the response rather than from a capability, and that is the choice this project has already made once: Talk does advertise a `spreed` capability, so the alternative is real, but acting on the capability means either an extra request or threading a `CapabilitySet` through every caller — and the two callers here differ, one having just validated the server and one not. A missing app answers `404` regardless, which Rainmaker surfaces as `notFound`, so the response is authoritative where a capability is only a prediction. The same reasoning is on record in `DECISIONS.md` for how iOS decides its notifications app is missing. The cost accepted is one request per refresh against an instance that will never have Talk.
    ///
    /// Only a `404` clears what was stored. Every other failure leaves the previous list in place, for the reason a failed app-list refresh does: an unreachable server has told us nothing, and emptying a Spotlight index because a laptop woke up on a captive portal would be reading silence as an answer.
    static func refreshConversations(using server: Server) async {
        do {
            let conversations = try await server.conversations()
            let stored = conversations.map { ConversationTransferObject(id: $0.token, name: $0.displayName, kind: kind(of: $0.type), lastActivity: $0.lastActivity, avatarVersion: $0.avatarVersion) }
            logger.notice("Fetched \(stored.count, privacy: .public) Talk conversation(s)")
            await AccountStore.shared.persist(conversations: stored)
        } catch RainmakerError.notFound {
            logger.notice("The Talk conversations endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")
            await AccountStore.shared.deleteConversations()
        } catch {
            logger.notice("Could not refresh the Talk conversations; keeping the previous list: \(error.localizedDescription)")
        }
    }

    /// `kind(of:)` is the number the server uses for a conversation type, recovered from the value the network library decoded it into.
    ///
    /// It is a mapping rather than a property read because `Rainmaker.ConversationType` is a closed Swift enum over an open set and offers no way back to the number it was decoded from — it encodes itself as a name instead. The `other` case is what carries a kind this library has not been taught, and passing its number straight through is what lets a server invent one without this app losing the conversation.
    private static func kind(of type: ConversationType) -> ConversationKind {
        switch type {
            case .oneToOne: .oneToOne
            case .group: .group
            case .publicConversation: .publicConversation
            case .changelog: .changelog
            case .formerOneToOne: .formerOneToOne
            case .noteToSelf: .noteToSelf
            case let .other(rawValue): ConversationKind(rawValue: rawValue)
        }
    }
}
