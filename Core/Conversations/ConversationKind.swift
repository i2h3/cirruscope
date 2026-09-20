// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ConversationKind` is what kind of Nextcloud Talk conversation something is, as the server numbers them.
///
/// It is a structure with a raw value rather than a Swift `enum` because the set is open: the server numbers the kinds it knows today and is free to add another, and a client that models this as a closed enum either fails to decode a conversation of a kind it has not heard of, or needs a catch-all case carrying an associated value — which cannot also be a `RawRepresentable` that round-trips. Keeping the number and naming the known ones beside it means an unrecognized kind survives being stored and read back unchanged, and nothing has to decide what to do about it before it is asked to.
/// The number is the server's own, which is why it is what gets persisted. Talk's REST API does not name these in its payload; it sends the integer.
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
