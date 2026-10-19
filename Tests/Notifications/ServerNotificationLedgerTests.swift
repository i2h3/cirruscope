// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerNotificationLedgerTests` covers how a fetch's answer is admitted to the record of notifications already seen: in the order the fetches were made, only while its account is signed in, and with the record written before anything may be posted.
///
/// It exists because the ledger is where two fetches in one process, and a sign-out landing between them, are kept from announcing a notification twice, announcing one for an account that is gone, or leaving a record behind for the next account to inherit.
/// Every case builds its own ledger over a file in a directory of its own under `URL.temporaryDirectory`, removed when the case's suite instance is released, and a `KeychainStandIn`, so no case reads or writes the developer's real record or credentials.
///
final class ServerNotificationLedgerTests {
    ///
    /// `directory` is this case's own directory, holding the record file.
    ///
    private let directory: URL

    ///
    /// `fileURL` is where this case's ledger keeps the record.
    ///
    private let fileURL: URL

    ///
    /// `keychain` is this case's stand-in for the Keychain, with `alice` signed in to begin with.
    ///
    private let keychain: KeychainStandIn

    ///
    /// `ledger` is this case's ledger.
    ///
    private let ledger: ServerNotificationLedger

    init() throws {
        directory = URL.temporaryDirectory.appending(component: "ServerNotificationLedgerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(component: "ServerNotifications.json", directoryHint: .notDirectory)

        let keychain = KeychainStandIn(signedIn: [ServerNotificationFixture.alice])
        self.keychain = keychain
        ledger = ServerNotificationLedger(fileURL: fileURL, storedCredentials: { try keychain.credentials(for: $0) })
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Admitting

    @Test
    func `The first answer is a first look and writes the record, and the next posts the difference`() throws {
        let first = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)
        let second = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1, 2, 3]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)

        let firstPlan = try #require(Self.plan(from: first))
        let secondPlan = try #require(Self.plan(from: second))

        #expect(firstPlan.isBaseline)
        #expect(firstPlan.post.isEmpty)
        #expect(secondPlan.post.map(\.id) == [3])
        #expect(Self.recordOnDisk(at: fileURL) == ServerNotificationFixture.record([1, 2, 3], highWater: 3, for: ServerNotificationFixture.alice))
    }

    @Test
    func `An answer whose fetch began before one already admitted is turned away`() {
        let earlier = ledger.issueTicket()
        let later = ledger.issueTicket()

        _ = ledger.commit(later, listing: ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)
        let stale = ledger.commit(earlier, listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)

        #expect(stale == .superseded)
        #expect(Self.recordOnDisk(at: fileURL)?.notificationIDs == [1, 2])
    }

    @Test
    func `Answers admitted in the order their fetches began are all admitted`() {
        let earlier = ledger.issueTicket()
        let later = ledger.issueTicket()

        #expect(Self.plan(from: ledger.commit(earlier, listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)) != nil)
        #expect(Self.plan(from: ledger.commit(later, listing: ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)) != nil)
    }

    @Test
    func `An outcome without a listing claims its place in the same order`() {
        let earlier = ledger.issueTicket()
        let later = ledger.issueTicket()

        #expect(ledger.admit(later))
        #expect(ledger.admit(earlier) == false)
        #expect(ledger.commit(earlier, listing: [], account: ServerNotificationFixture.alice, delivered: [], mayPost: true) == .superseded)
    }

    @Test(arguments: [nil, ServerNotificationFixture.aliceNewPassword, ServerNotificationFixture.bob] as [ServerAccount?])
    func `An answer for an account no longer signed in is turned away and writes nothing`(signedIn: ServerAccount?) {
        keychain.signOut()

        if let signedIn {
            keychain.signIn(signedIn)
        }

        let commit = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)

        #expect(commit == .notSignedIn)
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) == false)
    }

    @Test
    func `An answer is turned away while the Keychain refuses to say who is signed in`() {
        keychain.refuse(true)

        let commit = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)

        #expect(commit == .keychainUnreadable)
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) == false)
    }

    @Test
    func `Whether an account is still signed in is answered the way a refresh asks it`() {
        #expect(ledger.admission(of: ServerNotificationFixture.alice) == .admitted)
        #expect(ledger.admission(of: ServerNotificationFixture.aliceNewPassword) == .signedInAgain)
        #expect(ledger.admission(of: ServerNotificationFixture.otherServer) == .signedOut)

        keychain.refuse(true)

        #expect(ledger.admission(of: ServerNotificationFixture.alice) == .keychainUnreadable)
    }

    // MARK: - Clearing

    @Test
    func `An answer after a sign-out cleared the record writes nothing while nobody is signed in`() {
        _ = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)
        let late = ledger.issueTicket()

        keychain.signOut()
        ledger.clear()

        #expect(ledger.commit(late, listing: ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true) == .notSignedIn)
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) == false)
    }

    @Test
    func `An answer after the record was cleared is a first look again`() throws {
        _ = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)
        ledger.clear()

        let plan = try #require(Self.plan(from: ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)))

        #expect(plan.isBaseline)
        #expect(plan.post.isEmpty)
    }

    @Test
    func `Taking back a record spares one made for another account since`() {
        keychain.signIn(ServerNotificationFixture.bob)
        _ = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.bob, delivered: [], mayPost: true)

        ledger.clear(ifRecordedFor: ServerNotificationRecipient(ServerNotificationFixture.alice))
        #expect(Self.recordOnDisk(at: fileURL)?.recipient == ServerNotificationRecipient(ServerNotificationFixture.bob))

        ledger.clear(ifRecordedFor: ServerNotificationRecipient(ServerNotificationFixture.bob))
        #expect(Self.recordOnDisk(at: fileURL) == nil)
    }

    // MARK: - The file

    @Test
    func `A record that cannot be decoded makes the next answer a first look`() throws {
        try Data("not a record".utf8).write(to: fileURL)

        let plan = try #require(Self.plan(from: ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)))

        #expect(plan.isBaseline)
        #expect(Self.recordOnDisk(at: fileURL) == ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice))
    }

    @Test
    func `A record that cannot be written posts nothing and still withdraws`() throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false))
        }

        _ = ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([1]), account: ServerNotificationFixture.alice, delivered: [], mayPost: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path(percentEncoded: false))

        let plan = try #require(Self.plan(from: ledger.commit(ledger.issueTicket(), listing: ServerNotificationFixture.items([2]), account: ServerNotificationFixture.alice, delivered: [ServerNotificationFixture.delivered(1, for: ServerNotificationFixture.alice)], mayPost: true)))

        #expect(plan.isBaseline == false)
        #expect(plan.post.isEmpty)
        #expect(plan.withdraw == [1])
        #expect(Self.recordOnDisk(at: fileURL)?.notificationIDs == [1])
    }

    @Test
    func `A record survives being written and read back`() throws {
        let record = ServerNotificationFixture.record([3, 1, 2], highWater: 7, for: ServerNotificationFixture.subdirectory)

        #expect(try ServerNotificationLedger.decode(JSONEncoder().encode(record)) == record)
    }

    @Test
    func `The record holds a server, a login name and numbers, and nothing else`() throws {
        // A privacy guard: the file sits unencrypted in the shared container, so a field added to the record later,
        // a subject or the app password, must be a deliberate decision that changes this case too.
        let withHighWater = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ServerNotificationFixture.record([1], highWater: 1, for: ServerNotificationFixture.alice))) as? [String: Any]
        let withoutHighWater = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ServerNotificationFixture.record([], highWater: nil, for: ServerNotificationFixture.alice))) as? [String: Any]

        #expect(withHighWater.map { Set($0.keys) } == ["recipient", "notificationIDs", "highWater"])
        #expect((withHighWater?["recipient"] as? [String: Any]).map { Set($0.keys) } == ["server", "loginName"])
        #expect(withoutHighWater.map { Set($0.keys) } == ["recipient", "notificationIDs"])
    }

    // MARK: - Helpers

    ///
    /// `plan(from:)` is the plan an admitted commit carries, or `nil` for any other.
    ///
    private static func plan(from commit: ServerNotificationLedger.Commit) -> ServerNotificationPlan? {
        guard case let .admitted(plan) = commit else {
            return nil
        }

        return plan
    }

    ///
    /// `recordOnDisk(at:)` is the record the file at `fileURL` holds, or `nil` when there is none to read.
    ///
    private static func recordOnDisk(at fileURL: URL) -> ServerNotificationRecord? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return ServerNotificationLedger.decode(data)
    }
}
