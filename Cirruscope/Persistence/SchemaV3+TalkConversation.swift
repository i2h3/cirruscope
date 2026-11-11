// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `TalkConversation` is the v3 record for a Talk conversation the account takes part in exactly as it shipped in `1.2.0` and `1.2.1`.
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
}
