// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `TalkConversation` is the SwiftData record for one Nextcloud Talk conversation the connected account takes part in, persisted so Spotlight and the Shortcuts app can be offered them without the server having been asked first.
///
/// It is the persistent counterpart of the value-type `ConversationTransferObject`; `AccountStore` maps between the two so nothing outside the store ever holds a managed object. `AccountStore.persist(conversations:)` upserts these by `token` — updating existing rows and deleting ones the server no longer lists — so a conversation keeps its identity across a refresh rather than being torn down and rebuilt, which is what lets a donated Spotlight item stay the same item.
///
/// It is named for the app rather than for the thing, unlike `ServerApp`, and that is not decoration: Rainmaker exports a public `Conversation`, and a record of the same name in this module would shadow it in every file that imports both. The project has met this before and answered it the same way, which is why the keyboard-shortcut record is not called `AppShortcut`.
///
/// Two fields the server reports are deliberately absent. How many messages are unread, and whether any of them mentions the account, are both true only for as long as nobody reads anything — and what reads this record is an index that is refreshed when the conversation *list* changes, not when a message arrives. See `ConversationTransferObject` for why a sometimes-right count is worse than none.
@Model
final class TalkConversation {
    /// `token` is what Talk addresses the conversation by, and what the route opening it requires.
    var token: String

    /// `name` is the conversation's display name as the server resolved it.
    var name: String

    /// `kind` is the number the server uses for what kind of conversation this is; see `ConversationKind`.
    ///
    /// Stored as the number rather than as a name because the set is open and the server's own payload is numeric, so a kind this build has never heard of survives being stored and read back.
    var kind: Int

    /// `lastActivity` is when something last happened in the conversation, which is the order these are listed in.
    var lastActivity: Date

    /// `avatarVersion` is the marker the server changes when the conversation's image changes, kept for cache bookkeeping rather than for display.
    var avatarVersion: String

    /// `account` is the account this conversation belongs to; it is the inverse of `Account.conversations`.
    var account: Account?

    init(token: String, name: String, kind: Int, lastActivity: Date, avatarVersion: String, account: Account? = nil) {
        self.token = token
        self.name = name
        self.kind = kind
        self.lastActivity = lastActivity
        self.avatarVersion = avatarVersion
        self.account = account
    }
}
