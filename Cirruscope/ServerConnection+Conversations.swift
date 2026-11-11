// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s Talk conversations: fetching what the server lists and recording it.
extension ServerConnection {
    /// `refreshConversations(using:)` fetches the Talk conversations the authenticated `server` lists and persists them, or clears what was stored when the server has no Talk app.
    static func refreshConversations(using server: Server) async {
        let address = server.address
        let credentials = credentials(of: server)

        guard await isStillSignedIn(at: address, as: credentials) else {
            logger.notice("The account this refresh was begun for is no longer signed in; not asking for Talk conversations")
            return
        }

        do {
            let conversations = try await server.conversations()
            let stored = conversations.map { ConversationTransferObject(id: $0.token, name: $0.displayName, kind: kind(of: $0.type), lastActivity: $0.lastActivity, avatarVersion: $0.avatarVersion) }
            logger.notice("Fetched \(stored.count, privacy: .public) Talk conversation(s)")

            let recorded = await record("the Talk conversations", fetchedFrom: address, as: credentials) {
                AccountStore.shared.persist(conversations: stored)
            }

            guard recorded else {
                return
            }

            await refreshConversationAvatars(for: stored, using: server)
        } catch RainmakerError.notFound {
            logger.notice("The Talk conversations endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")

            await record("the absence of the Talk app", fetchedFrom: address, as: credentials) {
                AccountStore.shared.deleteConversations()
            }
        } catch {
            logger.notice("Could not refresh the Talk conversations; keeping the previous list: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `refreshConversationAvatars(for:using:)` fetches the picture of every conversation just listed, and announces the list again once they have landed.
    private static func refreshConversationAvatars(for conversations: [ConversationTransferObject], using server: Server) async {
        guard let credentials = Keychain.credentials(for: server.address) else {
            return
        }

        let identified = conversations.map { (token: $0.id, avatarVersion: $0.avatarVersion) }
        let didFetchAny = await ConversationAvatars.shared.refresh(conversations: identified, accountName: credentials.user, on: server)

        // These are pictures of people, and a sign-out while they were downloading has emptied the caches already;
        // one that landed after it would otherwise outlive it.
        await AccountStore.shared.forgetCachesIfSignedOut()

        guard didFetchAny else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .conversationsDidChange, object: nil)
        }
    }

    /// `kind(of:)` is the number the server uses for a conversation type, recovered from the value the network library decoded it into.
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
