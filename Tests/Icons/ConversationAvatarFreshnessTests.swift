// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ConversationAvatarFreshnessTests` pins when `ConversationAvatars` asks the server again about a conversation's picture: once the last answer is a week old, whether that answer was a picture or a refusal.
///
/// The suite exists because the rule once held for pictures and silently not for refusals. Every launch builds an entity for every conversation, which reads each cached answer, and reading a refusal remembered it in memory in a way that was consulted before the file's date — so a refusal older than a week was renewed at every launch and never asked about again, and a one-to-one conversation whose other party later uploaded a photograph kept the Talk mark for good.
///
/// Each case works on its own `AssetCache` over a directory under `URL.temporaryDirectory`, removed when the case ends, so nothing here touches the shared App Group cache or the developer's real cached pictures.
/// It asks `pendingFetches(for:accountName:serverAddress:now:)` rather than calling `refresh`, which would need a `Rainmaker.Server` and a network; the decision it makes is the whole of what is being pinned.
final class ConversationAvatarFreshnessTests {
    /// `directory` is this case's own cache directory.
    let directory: URL

    /// `cache` is the cache over `directory`.
    let cache: AssetCache

    /// `avatars` is the store under test, over `cache`.
    let avatars: ConversationAvatars

    /// `serverAddress` is the server every case's conversation lives on.
    let serverAddress = URL(string: "https://cloud.example.com")!

    /// `accountName` is the account every case is signed in as.
    let accountName = "alice"

    /// `conversation` is the one conversation every case asks about.
    let conversation = (token: "abc123", avatarVersion: "v1")

    /// `day` is one day, in the unit dates are offset by.
    let day: TimeInterval = 24 * 60 * 60

    /// `key` is what `conversation`'s answer is cached under.
    var key: String {
        ConversationAvatars.cacheKey(token: conversation.token, avatarVersion: conversation.avatarVersion, accountName: accountName, serverAddress: serverAddress)
    }

    /// `init()` creates this case's cache directory and the store over it.
    init() throws {
        directory = URL.temporaryDirectory.appending(path: "CirruscopeConversationAvatarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = AssetCache(directory: directory)
        avatars = ConversationAvatars(cache: cache)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `storeAnswer(_:answeredDaysAgo:)` caches `data` as the server's answer about `conversation`, dated `days` before now.
    ///
    /// Empty `data` is a refusal, anything else a picture; the date is set on the file, because the file's date is what records when the server answered.
    private func storeAnswer(_ data: Data, answeredDaysAgo days: Double) throws {
        cache.store(data, forKey: key)
        try dateAnswer(daysAgo: days)
    }

    /// `dateAnswer(daysAgo:)` sets the date of the answer already cached about `conversation` to `days` before now.
    private func dateAnswer(daysAgo days: Double) throws {
        let fileURL = try #require(cache.localURL(forKey: key))
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-days * day)], ofItemAtPath: fileURL.path(percentEncoded: false))
    }

    /// `readAnswer()` reads the cached answer about `conversation` the way building its entity does, which every launch does for every conversation.
    @discardableResult
    private func readAnswer() -> Bool {
        avatars.image(forToken: conversation.token, avatarVersion: conversation.avatarVersion, accountName: accountName, serverAddress: serverAddress) != nil
    }

    /// `isPending(now:)` reports whether `conversation`'s picture would be asked for at `now`.
    private func isPending(now: Date = .now) -> Bool {
        avatars.pendingFetches(for: [conversation], accountName: accountName, serverAddress: serverAddress, now: now).contains { $0.token == conversation.token }
    }

    @Test
    func `A conversation nothing has been cached for is asked about`() {
        #expect(isPending())
    }

    @Test(arguments: [(1.0, false), (6.0, false), (8.0, true), (30.0, true)])
    func `A cached picture is asked about again once it is a week old`(daysAgo: Double, expectsFetch: Bool) throws {
        try storeAnswer(Data([0x89, 0x50, 0x4E, 0x47]), answeredDaysAgo: daysAgo)

        #expect(isPending() == expectsFetch)
    }

    @Test(arguments: [(1.0, false), (6.0, false), (8.0, true), (30.0, true)])
    func `A refusal read at launch is asked about again once it is a week old`(daysAgo: Double, expectsFetch: Bool) throws {
        try storeAnswer(Data(), answeredDaysAgo: daysAgo)

        #expect(readAnswer() == false)

        #expect(isPending() == expectsFetch)
    }

    @Test
    func `A refusal remembered in this process stands without its file, and only for a week`() throws {
        try storeAnswer(Data(), answeredDaysAgo: 1)
        readAnswer()

        // A file that could not be kept leaves the date remembered in memory as the only record.
        cache.remove(forKey: key)

        #expect(isPending() == false)
        #expect(isPending(now: .now.addingTimeInterval(7 * day)))
    }

    @Test
    func `A refusal remembered in this process is not dated back by an older file`() throws {
        try storeAnswer(Data(), answeredDaysAgo: 1)
        readAnswer()

        // An older refusal left on disk, as when a newer answer could not be written over it.
        try dateAnswer(daysAgo: 8)
        readAnswer()

        #expect(isPending() == false)
    }

    @Test
    func `Clearing forgets a remembered refusal`() throws {
        try storeAnswer(Data(), answeredDaysAgo: 1)
        readAnswer()
        cache.remove(forKey: key)

        avatars.clear()

        #expect(isPending())
    }
}
