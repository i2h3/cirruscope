// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Synchronization

/// `ServerNotificationLedger` keeps the record of the server's notifications already seen, and admits each fetch's answer to it in the order the fetches were made.
final class ServerNotificationLedger: Sendable {
    /// `Ticket` is a fetch's place in the order the fetches were made.
    struct Ticket: Comparable, Sendable {
        /// `value` is the ticket's number, higher for a later fetch.
        let value: UInt64

        ///
        /// `<(_:_:)` orders tickets by when their fetches were made.
        ///
        static func < (lhs: Ticket, rhs: Ticket) -> Bool {
            lhs.value < rhs.value
        }
    }

    /// `Commit` is what admitting one fetch's answer came to.
    enum Commit: Equatable, Sendable {
        /// `admitted` carries the plan decided for the answer, whose record has been written.
        case admitted(ServerNotificationPlan)

        /// `superseded` means a later fetch's answer was admitted first, so this one changes nothing.
        case superseded

        /// `notSignedIn` means the account the answer was fetched as is no longer the one signed in.
        case notSignedIn

        /// `keychainUnreadable` means the Keychain refused to say who is signed in, so nothing was admitted.
        case keychainUnreadable
    }

    /// `State` is the order the ledger keeps between fetches.
    private struct State {
        /// `nextTicket` is the number of the ticket issued last.
        var nextTicket: UInt64 = 0

        /// `lastAdmitted` is the number of the latest ticket whose answer was admitted, or `nil` while none has been.
        var lastAdmitted: UInt64?
    }

    /// `shared` is the process-wide ledger over the record in the App Group container, which every fetch and every sign-out goes through.
    static let shared = ServerNotificationLedger(fileURL: AppGroup.containerURL.appending(component: "ServerNotifications.json", directoryHint: .notDirectory), storedCredentials: { try Keychain.storedCredentials(for: $0) })

    /// `logger` records every change to the record under the `ServerNotificationLedger` category.
    private let logger = Logger(for: ServerNotificationLedger.self)

    /// `state` is the ticket order, behind the lock every admission and every clearing takes.
    private let state = Mutex(State())

    /// `fileURL` is where the record is kept.
    private let fileURL: URL

    /// `storedCredentials` reads the credentials the Keychain holds for a server, throwing when the Keychain refuses to say.
    private let storedCredentials: @Sendable (URL) throws -> Credentials?

    /// `init(fileURL:storedCredentials:)` builds a ledger over the record at `fileURL`, asking `storedCredentials` who is signed in.
    init(fileURL: URL, storedCredentials: @escaping @Sendable (URL) throws -> Credentials?) {
        self.fileURL = fileURL
        self.storedCredentials = storedCredentials
    }

    /// `issueTicket()` takes the next place in the order, which a fetch does before it starts.
    func issueTicket() -> Ticket {
        state.withLock { state in
            state.nextTicket &+= 1
            return Ticket(value: state.nextTicket)
        }
    }

    /// `admit(_:)` admits an answer that writes nothing to the record, such as a refusal or no account, answering whether it is still the latest.
    func admit(_ ticket: Ticket) -> Bool {
        state.withLock { state in
            if let lastAdmitted = state.lastAdmitted, lastAdmitted > ticket.value {
                return false
            }

            state.lastAdmitted = ticket.value
            return true
        }
    }

    /// `commit(_:listing:account:delivered:mayPost:)` admits the answer `listing`, fetched as `account` with `ticket`, deciding its plan against the record and what Notification Center holds, and writing the record the plan names.
    ///
    /// A record that cannot be written turns the plan into one that posts nothing, since posting what was not recorded would post it again on every fetch; its withdrawals still stand.
    func commit(_ ticket: Ticket, listing: [ServerNotificationTransferObject], account: ServerAccount, delivered: [ServerNotificationPlan.Delivered], mayPost: Bool) -> Commit {
        state.withLock { state in
            if let lastAdmitted = state.lastAdmitted, lastAdmitted > ticket.value {
                logger.notice("Turned away notifications fetched with ticket \(ticket.value, privacy: .public), a later fetch having been admitted already")
                return .superseded
            }

            let storedCredentials: Credentials?

            do {
                storedCredentials = try self.storedCredentials(account.server)
            } catch {
                logger.error("The Keychain could not be read, so the notifications fetched with ticket \(ticket.value, privacy: .public) were not admitted: \(error.localizedDescription, privacy: .public)")
                return .keychainUnreadable
            }

            guard RefreshAdmission.forAdopting(fetchedAs: account.credentials, keychainHolds: storedCredentials) == .admitted else {
                logger.notice("Turned away notifications fetched with ticket \(ticket.value, privacy: .public) for an account that is no longer signed in")
                return .notSignedIn
            }

            let recorded = load()
            var plan = ServerNotificationPlan.make(listing: listing, for: ServerNotificationRecipient(account), recorded: recorded, delivered: delivered, mayPost: mayPost)

            if plan.record != recorded {
                do {
                    try write(plan.record)
                    logger.notice("Recorded \(plan.record.notificationIDs.count, privacy: .public) notification(s), the highest ever \(plan.record.highWater ?? 0, privacy: .public)\(plan.isBaseline ? ", as the first look at this account" : "", privacy: .public)")
                } catch {
                    logger.error("Could not write the record of notifications already seen, so posting none of them: \(error.localizedDescription, privacy: .public)")
                    plan = plan.withoutPosting()
                }
            } else {
                logger.debug("The record of notifications already seen is unchanged")
            }

            state.lastAdmitted = ticket.value

            return .admitted(plan)
        }
    }

    /// `admission(of:)` is whether `account` is still the one signed in, asked without the lock, for a check made between posting one notification and the next.
    func admission(of account: ServerAccount) -> RefreshAdmission {
        do {
            return try RefreshAdmission.forAdopting(fetchedAs: account.credentials, keychainHolds: storedCredentials(account.server))
        } catch {
            return .keychainUnreadable
        }
    }

    /// `clear()` forgets the record, which every sign-out does.
    func clear() {
        state.withLock { _ in
            remove()
        }

        logger.notice("Forgot the record of notifications already seen")
    }

    /// `clear(ifRecordedFor:)` forgets the record only if it was made for `recipient`, for taking back what a fetch overtaken by a sign-out recorded without touching a record a later sign-in has made since.
    func clear(ifRecordedFor recipient: ServerNotificationRecipient) {
        state.withLock { _ in
            guard load()?.recipient == recipient else {
                return
            }

            remove()
            logger.notice("Forgot the record of notifications already seen, made for an account that signed out while it was being acted on")
        }
    }

    /// `decode(_:)` is the record `data` holds, or `nil` when it holds none that this release can read.
    static func decode(_ data: Data) -> ServerNotificationRecord? {
        try? JSONDecoder().decode(ServerNotificationRecord.self, from: data)
    }

    /// `load()` is the record kept at `fileURL`, or `nil` when there is none or it cannot be read, either of which makes the next fetch a first look.
    private func load() -> ServerNotificationRecord? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        guard let record = Self.decode(data) else {
            logger.notice("The record of notifications already seen could not be decoded and is being ignored")
            return nil
        }

        return record
    }

    /// `write(_:)` replaces the record kept at `fileURL` with `record`, atomically.
    private func write(_ record: ServerNotificationRecord) throws {
        try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
    }

    /// `remove()` deletes the record kept at `fileURL`, if there is one.
    private func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
