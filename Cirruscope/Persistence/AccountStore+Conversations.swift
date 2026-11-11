// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AccountStore`'s Talk conversations: reading them back as value snapshots, and writing what a refresh found.
extension AccountStore {
    /// `conversations` are the connected account's Talk conversations as value snapshots, most recently active first.
    var conversations: [ConversationTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.conversations
            .map { ConversationTransferObject(id: $0.token, name: $0.name, kind: ConversationKind(rawValue: $0.kind), lastActivity: $0.lastActivity, avatarVersion: $0.avatarVersion) }
            .sortedByActivity()
    }

    /// `conversation(forToken:)` is the connected account's conversation with `token` as a value snapshot, or `nil` when the account has no such conversation.
    func conversation(forToken token: String) -> ConversationTransferObject? {
        guard let conversation = currentAccount(createIfNeeded: false)?.conversations.first(where: { $0.token == token }) else {
            return nil
        }

        return ConversationTransferObject(id: conversation.token, name: conversation.name, kind: ConversationKind(rawValue: conversation.kind), lastActivity: conversation.lastActivity, avatarVersion: conversation.avatarVersion)
    }

    /// `persist(conversations:)` upserts the account's Talk conversations: existing rows are updated in place, new ones inserted, and ones the server no longer lists deleted.
    func persist(conversations: [ConversationTransferObject]) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        let existingConversations = account.conversations
        var existingByToken: [String: TalkConversation] = [:]
        for conversation in existingConversations {
            existingByToken[conversation.token] = conversation
        }

        var incomingTokens: Set<String> = []
        var inserted = 0
        var updated = 0
        var pruned = 0

        // A token already seen in this list is skipped rather than inserted twice, matching `persist(serverApps:)`:
        // two rows sharing one identity would leave the read's ordering with a tie it cannot break. No real server
        // sends duplicates.
        for conversation in conversations where incomingTokens.contains(conversation.id) == false {
            incomingTokens.insert(conversation.id)

            if let existing = existingByToken[conversation.id] {
                existing.name = conversation.name
                existing.kind = conversation.kind.rawValue
                existing.lastActivity = conversation.lastActivity
                existing.avatarVersion = conversation.avatarVersion
                updated += 1
            } else {
                context.insert(TalkConversation(token: conversation.id, name: conversation.name, kind: conversation.kind.rawValue, lastActivity: conversation.lastActivity, avatarVersion: conversation.avatarVersion, account: account))
                inserted += 1
            }
        }

        for conversation in existingConversations where incomingTokens.contains(conversation.token) == false {
            context.delete(conversation)
            pruned += 1
        }

        logger.notice("Persisting conversations: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated, \(pruned, privacy: .public) pruned, \(incomingTokens.count, privacy: .public) stored")
        save()
        notifyChange(.conversationsDidChange)
    }

    /// `deleteConversations()` removes every stored conversation, for a server that turns out not to offer Talk at all.
    ///
    /// Separate from a refresh finding none, though the stored result is the same, because the two are different facts and only one of them is worth acting on elsewhere: an account that has no conversations may yet have one tomorrow, while an instance without the Talk app will not. What matters here is that a server which had Talk and no longer does does not keep answering Spotlight with conversations nobody can open.
    func deleteConversations() {
        guard let account = currentAccount(createIfNeeded: false) else {
            return
        }

        guard account.conversations.isEmpty == false else {
            return
        }

        logger.notice("Dropping every stored conversation (\(account.conversations.count, privacy: .public))")

        for conversation in account.conversations {
            context.delete(conversation)
        }

        save()
        notifyChange(.conversationsDidChange)
    }
}
