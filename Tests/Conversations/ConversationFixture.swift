// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation

/// `ConversationFixture` is the corpus of Talk conversations the conversation suites run their cases over.
///
/// Shared through a named type rather than copied between suites, for the reason `ServerAppFixture` is: two suites with their own copies cannot be told apart from two suites that agree, and the first time one of them gains a case the other should have had, nothing says so.
/// The timestamps are fixed rather than relative to now, so a case asserting an order asserts the same thing whenever it runs.
enum ConversationFixture {
    /// `design` is an ordinary group conversation.
    static let design = ConversationTransferObject(id: "des1gn00", name: "Design", kind: .group, lastActivity: Date(timeIntervalSince1970: 1_700_000_300), avatarVersion: "v1")

    /// `alice` is a one-to-one conversation, whose display name is a person's name.
    static let alice = ConversationTransferObject(id: "al1ce000", name: "Alice Adams", kind: .oneToOne, lastActivity: Date(timeIntervalSince1970: 1_700_000_200), avatarVersion: "v1")

    /// `noteToSelf` is the conversation the server gives every account for talking to itself.
    static let noteToSelf = ConversationTransferObject(id: "n0te5elf", name: "Note to self", kind: .noteToSelf, lastActivity: Date(timeIntervalSince1970: 1_700_000_100), avatarVersion: "v1")

    /// `all` is every fixture, in no meaningful order — the server does not sort these either, which is the point.
    static let all = [alice, noteToSelf, design]
}
