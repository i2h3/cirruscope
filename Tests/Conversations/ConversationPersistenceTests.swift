// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ConversationPersistenceTests` covers what `AccountStore` does with the Talk conversations a refresh found: the upsert, the pruning, the order they come back in, and that a write announces itself while a read does not.
///
/// The case that earns the suite is the upsert. Matching an existing row by token rather than replacing the list is what keeps a conversation the same record across a refresh, and that is not tidiness: Spotlight is donated an item per conversation, and a list torn down and rebuilt on every launch would delete and re-add every one of them rather than leaving them alone.
@MainActor
@Suite(.serialized)
struct ConversationPersistenceTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    @Test
    func `A store with no account has no conversations`() {
        #expect(harness.store.conversations.isEmpty)
    }

    @Test
    func `Persisting conversations for the first time creates the account and stores them`() {
        harness.store.persist(conversations: ConversationFixture.all)

        #expect(harness.store.conversations.count == 3)
    }

    @Test
    func `Conversations are returned most recently active first, whatever order the server sent them in`() {
        harness.store.persist(conversations: ConversationFixture.all)

        #expect(harness.store.conversations.map(\.id) == ["des1gn00", "al1ce000", "n0te5elf"])
    }

    @Test
    func `A refresh updates a conversation in place rather than replacing it`() {
        harness.store.persist(conversations: [ConversationFixture.design])

        let renamed = ConversationTransferObject(id: ConversationFixture.design.id, name: "Design and Research", kind: .group, lastActivity: Date(timeIntervalSince1970: 1_700_000_900), avatarVersion: "v2")
        harness.store.persist(conversations: [renamed])

        #expect(harness.store.conversations.count == 1)
        #expect(harness.store.conversations.first?.name == "Design and Research")
        #expect(harness.store.conversations.first?.avatarVersion == "v2")
    }

    @Test
    func `A refresh deletes a conversation the server no longer lists`() {
        harness.store.persist(conversations: ConversationFixture.all)
        harness.store.persist(conversations: [ConversationFixture.design])

        #expect(harness.store.conversations.map(\.id) == ["des1gn00"])
    }

    @Test
    func `Persisting an empty list deletes every conversation`() {
        harness.store.persist(conversations: ConversationFixture.all)
        harness.store.persist(conversations: [])

        #expect(harness.store.conversations.isEmpty)
    }

    @Test
    func `The same conversation listed twice is stored once`() {
        harness.store.persist(conversations: [ConversationFixture.design, ConversationFixture.design])

        #expect(harness.store.conversations.count == 1)
    }

    @Test
    func `A conversation is found by its token, and an unknown token finds nothing`() {
        harness.store.persist(conversations: ConversationFixture.all)

        #expect(harness.store.conversation(forToken: "al1ce000")?.name == "Alice Adams")
        #expect(harness.store.conversation(forToken: "n0sucht0ken") == nil)
    }

    @Test
    func `A kind the server has invented survives being stored and read back`() {
        let exotic = ConversationTransferObject(id: "ex0t1c00", name: "Something New", kind: ConversationKind(rawValue: 99), lastActivity: Date(timeIntervalSince1970: 1_700_000_000), avatarVersion: "")
        harness.store.persist(conversations: [exotic])

        // The whole reason the kind is a raw number rather than a closed enum: a build that has never heard of this
        // kind must still be able to store the conversation and hand it back unchanged.
        #expect(harness.store.conversation(forToken: "ex0t1c00")?.kind == ConversationKind(rawValue: 99))
    }

    @Test
    func `Deleting the account takes its conversations with it`() {
        harness.store.persist(conversations: ConversationFixture.all)
        harness.store.deleteAccount()

        #expect(harness.store.conversations.isEmpty)
    }

    @Test
    func `Every write announces the conversations changed, and reading announces nothing`() {
        harness.store.persist(conversations: ConversationFixture.all)
        #expect(harness.announcements == [.conversationsDidChange])

        _ = harness.store.conversations
        #expect(harness.announcements == [.conversationsDidChange])
    }

    @Test
    func `Dropping the conversations of a server without Talk announces once, and again does nothing`() {
        harness.store.persist(conversations: ConversationFixture.all)
        harness.store.deleteConversations()

        #expect(harness.store.conversations.isEmpty)
        #expect(harness.announcements == [.conversationsDidChange, .conversationsDidChange])

        // Nothing to delete is not a change, so it is not announced: the Spotlight index would otherwise be
        // rebuilt on every launch against a server that has never had Talk.
        harness.store.deleteConversations()
        #expect(harness.announcements.count == 2)
    }
}
