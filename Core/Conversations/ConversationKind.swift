// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ConversationKind` is what kind of Nextcloud Talk conversation something is, as the server numbers them.
struct ConversationKind: RawRepresentable, Hashable, Codable, Sendable {
    /// `rawValue` is the number the server uses for this kind.
    let rawValue: Int

    /// `oneToOne` is a conversation between the account and exactly one other person.
    static let oneToOne = ConversationKind(rawValue: 1)

    /// `group` is a conversation among a named group of people.
    static let group = ConversationKind(rawValue: 2)

    /// `publicConversation` is a conversation anyone holding its link can join.
    static let publicConversation = ConversationKind(rawValue: 3)

    /// `changelog` is the conversation Talk maintains on its own to announce its release notes.
    static let changelog = ConversationKind(rawValue: 4)

    /// `formerOneToOne` is what a one-to-one conversation becomes once the other person's account is gone.
    static let formerOneToOne = ConversationKind(rawValue: 5)

    /// `noteToSelf` is the conversation the server gives every account for talking to itself.
    static let noteToSelf = ConversationKind(rawValue: 6)
}
