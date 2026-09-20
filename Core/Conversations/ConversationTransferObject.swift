// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ConversationTransferObject` is a value-type snapshot of one Nextcloud Talk conversation the user takes part in.
///
/// It is the shape both apps pass around and the shape `AccountStore` is written with and read from, so nothing about the store's surface depends on the network library's own models — the same arrangement `ServerAppTransferObject` has, and what lets a test seed conversations without the test targets linking Rainmaker.
///
/// What it deliberately leaves out is as considered as what it carries. The server also reports how many messages are unread and whether any of them mentions the account, and neither is here: what reads these is Spotlight, which is handed a snapshot when the list changes and is not re-donated when a message arrives, so a stored unread count would be a number the app is confidently wrong about for as long as nobody opens Talk. A count that is only sometimes right is worse than no count, because there is nothing on the result to say which.
struct ConversationTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the conversation's token, which is what Talk addresses it by (e.g. `"a1b2c3d4"`).
    ///
    /// The token rather than the server's numeric identifier, deliberately: the route that opens a conversation requires a token, and a number could not satisfy it. It is also what the avatar endpoint takes.
    let id: String

    /// `name` is the conversation's display name, as the server resolved it — the other person's name in a one-to-one conversation, the group's name otherwise.
    let name: String

    /// `kind` is what kind of conversation it is, as the server numbers them.
    let kind: ConversationKind

    /// `lastActivity` is when something last happened in the conversation, which is the order these are listed in.
    let lastActivity: Date

    /// `avatarVersion` is the marker the server changes when the conversation's image changes.
    ///
    /// Carried for cache bookkeeping rather than for display, and not sufficient on its own: the server derives it from the path of a generic icon for a one-to-one conversation, so it is identical across all of them and never moves when the other person changes their photograph. Anything caching an image keys it by server, account, token and appearance as well, and bounds how long it keeps one regardless.
    let avatarVersion: String
}
