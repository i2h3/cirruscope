// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `UnreadNotifications` fetches the notifications the connected server still has queued for the user, and reports what that means for the app icon badge.
enum UnreadNotifications {
    /// `Outcome` is the closed set of results a fetch can have, carrying the notifications, and the account they were fetched as, only in the one case where there are any to carry.
    enum Outcome: Sendable {
        /// `fetched` carries the notifications currently queued, which is the empty array when there are none, and the account they were fetched as, which was still the signed-in one when the answer arrived.
        case fetched([ServerNotificationTransferObject], account: ServerAccount)

        /// `noAccount` reports that no usable credentials are stored, so there is no server to ask, or that the account a fetch asked for is no longer the configured one by the time it was answered.
        case noAccount

        /// `endpointUnavailable` reports the `404` an instance answers while its notifications app is absent or disabled.
        case endpointUnavailable

        /// `credentialsRejected` reports that the server answered the notifications request with HTTP 401, refusing the app password it was asked with.
        case credentialsRejected

        /// `cancelled` reports that the fetch was cancelled before it finished, which is what a background task running out of its allotted time looks like from in here.
        case cancelled

        /// `unreachable` reports every other failure, all of which are treated as transient.
        case unreachable

        /// `badgeUpdate` is what this outcome means for the app icon badge.
        var badgeUpdate: BadgeUpdate {
            switch self {
                case let .fetched(items, _):
                    .set(items.count)

                case .noAccount, .endpointUnavailable, .credentialsRejected:
                    .clear

                case .cancelled, .unreachable:
                    .unchanged
            }
        }
    }

    /// `BadgeUpdate` is one decision about what the app icon badge must show next.
    enum BadgeUpdate: Equatable, Sendable {
        /// `set` carries the number to show, which is zero when there is nothing unread.
        case set(Int)

        /// `clear` means the badge must show nothing, because there is nothing this app could be counting.
        case clear

        /// `unchanged` means the badge must be left exactly as it stands.
        case unchanged
    }

    /// `logger` records every fetch under the `UnreadNotifications` category.
    static let logger = Logger(for: UnreadNotifications.self)

    /// `fetch(reason:)` asks the connected server for the notifications queued for the user, resolving the account from the Keychain, and reports what came back.
    static func fetch(reason: StaticString) async -> Outcome {
        let accounts: [ServerAccount]

        do {
            accounts = try Keychain.storedAccounts()
        } catch {
            logger.error("The Keychain could not be read, so whether an account is configured is unknown (\(reason)): \(error.localizedDescription, privacy: .public)")
            return .unreachable
        }

        guard let account = accounts.first else {
            logger.notice("No account is configured, so there is nothing to fetch (\(reason))")
            return .noAccount
        }

        return await fetch(as: account, reason: reason, routine: false)
    }

    /// `fetch(as:reason:routine:)` asks the server `account` signs in to for the notifications queued for the user, and reports what came back.
    static func fetch(as account: ServerAccount, reason: StaticString, routine: Bool) async -> Outcome {
        let started = ContinuousClock.now
        let server = ServerConnection.authenticated(account)

        logger.log(level: routine ? .debug : .default, "Fetching unread notifications (\(reason))")

        do {
            let items = try await server.notifications()

            // A sign-out does not wait for a fetch under way, and the app password is revoked without waiting either,
            // so this can succeed for an account that is gone; publishing it would put that account's count back on
            // the app icon after the sign-out cleared it, and its notifications back in Notification Center.
            let storedCredentials: Credentials?

            do {
                storedCredentials = try Keychain.storedCredentials(for: account.server)
            } catch {
                logger.error("The Keychain could not be read after the fetch, so whether its account is still configured is unknown; discarding it (\(reason)): \(error.localizedDescription, privacy: .public)")
                return .unreachable
            }

            guard storedCredentials == account.credentials else {
                logger.notice("Fetched unread notifications for an account that is no longer the configured one; discarding them (\(reason))")
                return .noAccount
            }

            logger.log(level: routine ? .debug : .default, "Fetched \(items.count, privacy: .public) unread notification(s) in \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")

            let notifications = items.map { ServerNotificationTransferObject(id: $0.id, app: $0.app, creation: $0.creation, subject: $0.subject, message: $0.message, link: $0.link) }

            return .fetched(notifications, account: account)
        } catch is CancellationError {
            logger.error("Fetching unread notifications was cancelled after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            // `URLSession` reports Swift task cancellation as this rather than as `CancellationError`, and Rainmaker
            // calls `session.data(for:)` directly, so an expiring background task arrives here rather than above.
            logger.error("Fetching unread notifications was cancelled by the URL session after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .cancelled
        } catch RainmakerError.notFound {
            logger.notice("The notifications endpoint answered 404 after \(Self.milliseconds(since: started), privacy: .public) ms, so the notifications app is absent or disabled (\(reason))")
            return .endpointUnavailable
        } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
            logger.notice("The app password was rejected after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .credentialsRejected
        } catch {
            logger.notice("Could not fetch unread notifications after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason)): \(error.localizedDescription)")
            return .unreachable
        }
    }

    /// `milliseconds(since:)` is how long ago `start` was, in whole milliseconds, for the duration every line above carries.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
