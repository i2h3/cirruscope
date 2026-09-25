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
            await refreshConversationAvatars(for: stored, using: server)
        } catch RainmakerError.notFound {
            logger.notice("The Talk conversations endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")
            await AccountStore.shared.deleteConversations()
        } catch {
            logger.notice("Could not refresh the Talk conversations; keeping the previous list: \(error.localizedDescription)")
        }
    }

    /// `refreshConversationAvatars(for:using:)` fetches the picture of every conversation just listed, and announces the list again once they have landed.
    ///
    /// After the list rather than before it, and that ordering is the point: the conversations are what Spotlight needs first, so they are stored and announced immediately, and the pictures — one request each — arrive behind them. The second announcement is what puts those pictures into the index; it is sent only when something was actually fetched, so an unchanged account does not redonate everything to look exactly as it already does.
    /// This is the arrangement `refreshServerAppIcons(from:using:)` already uses for the app icons, including the hop to the main actor before posting, which is not optional: `NotificationCenter` delivers synchronously on the posting thread and every observer of this name is main-actor-isolated.
    private static func refreshConversationAvatars(for conversations: [ConversationTransferObject], using server: Server) async {
        guard let credentials = Keychain.credentials(for: server.address) else {
            return
        }

        let identified = conversations.map { (token: $0.id, avatarVersion: $0.avatarVersion) }
        let didFetchAny = await ConversationAvatars.shared.refresh(conversations: identified, accountName: credentials.user, on: server)

        guard didFetchAny else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .conversationsDidChange, object: nil)
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
