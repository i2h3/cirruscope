// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `RecentActivity` fetches the newest file activity of the connected server, prepared for a widget to draw.
enum RecentActivity {
    /// `Outcome` is the closed set of results a fetch can have, carrying the prepared rows only in the one case where there are any to carry.
    enum Outcome: Sendable {
        /// `fetched` carries the rows to draw, which is the empty array when the server has nothing to report — the widget's "All quiet", which is a success rather than a failure — and the account they were fetched as.
        ///
        /// The account travels with the rows so a caller can confirm, once it has acted on them, that it is still the one signed in, credentials and all: signing out and back in to the same server stores new credentials under the same address.
        case fetched([ActivityRow], account: ServerAccount)

        /// `noAccount` reports that the Keychain holds no usable credentials, so there is no server to ask.
        case noAccount

        /// `endpointUnavailable` reports that the instance offers no file activity: either the activity app answered `404`, or it is enabled but publishes no `files` filter.
        case endpointUnavailable

        /// `credentialsRejected` reports that the stored app password was refused, so it has been revoked on the server.
        case credentialsRejected

        /// `cancelled` reports that the fetch was cancelled before it finished, which is what a timeline refresh running out of its allotted time looks like from in here.
        case cancelled

        /// `unreachable` reports every other failure, all of which are treated as transient — and which the widget draws as its stale state, keeping the rows it last had.
        case unreachable
    }

    /// `logger` records every fetch under the `RecentActivity` category.
    static let logger = Logger(for: RecentActivity.self)

    /// `filterIdentifier` is the id of the server's file-activity filter, remembered for the life of the process once resolved.
    ///
    /// Resolving it costs a request of its own, and a widget refresh should not spend two round trips on every tick when the answer is a server-side configuration that does not change between them. A process that outlives such a change picks the new one up on its next launch, which for an extension is measured in minutes.
    private static let filterIdentifier = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// `fetch(limit:reason:)` asks the connected server for its newest file activity, reporting what came back.
    static func fetch(limit: Int, reason: StaticString) async -> Outcome {
        let started = ContinuousClock.now

        logger.notice("Fetching recent activity (\(reason))")

        let accounts: [ServerAccount]

        do {
            accounts = try Keychain.storedAccounts()
        } catch {
            logger.error("The Keychain could not be read, so whether an account is configured is unknown (\(reason)): \(error.localizedDescription, privacy: .public)")
            return .unreachable
        }

        guard let account = accounts.first else {
            // The credentials may still be in macOS's file-based Keychain, where the macOS app moves them from on its
            // next launch. Until it has, nothing is known about whether anybody is signed in, so this is not
            // `noAccount`, which would forget the rows the widget last drew.
            guard Keychain.holdsFileBasedItems() == false else {
                logger.notice("The credentials are still in the file-based Keychain, which the app has not moved them out of yet (\(reason))")
                return .unreachable
            }

            logger.notice("No account is configured, so there is nothing to fetch (\(reason))")
            return .noAccount
        }

        guard let server = ServerConnection.authenticated(address: account.server) else {
            logger.notice("No credentials are stored for the configured account, so there is nothing to fetch (\(reason))")
            return .noAccount
        }

        do {
            guard let filter = try await fileActivityFilter(on: server, reason: reason) else {
                logger.notice("The server publishes no file activity filter, so its activity app is absent or its files activities are switched off (\(reason))")
                return .endpointUnavailable
            }

            let page = try await server.activities(filter: filter, limit: limit)
            let rows = page.items.compactMap(ActivityRow.init)

            logger.notice("Fetched \(page.items.count, privacy: .public) activity item(s), \(rows.count, privacy: .public) drawable, in \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")

            return .fetched(rows, account: account)
        } catch is CancellationError {
            logger.error("Fetching recent activity was cancelled after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            // `URLSession` reports Swift task cancellation as this rather than as `CancellationError`, and Rainmaker
            // calls `session.data(for:)` directly, so an expiring refresh arrives here rather than above.
            logger.error("Fetching recent activity was cancelled by the URL session after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .cancelled
        } catch RainmakerError.notFound {
            logger.notice("The activity endpoint answered 404 after \(Self.milliseconds(since: started), privacy: .public) ms, so the activity app is absent or disabled (\(reason))")
            return .endpointUnavailable
        } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
            logger.notice("The stored app password was rejected after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .credentialsRejected
        } catch {
            logger.notice("Could not fetch recent activity after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason)): \(error.localizedDescription)")
            return .unreachable
        }
    }

    /// `fileActivityFilter(on:reason:)` is the id of the server's file-activity filter, asked for once per process and remembered, or `nil` when the instance publishes none.
    private static func fileActivityFilter(on server: Server, reason: StaticString) async throws -> String? {
        if let remembered = filterIdentifier.withLock({ $0 }) {
            return remembered
        }

        let filters = try await server.activityFilters()

        logger.notice("The server publishes \(filters.count, privacy: .public) activity filter(s): \(filters.map(\.id).joined(separator: ", "), privacy: .public) (\(reason))")

        guard let files = filters.first(where: { $0.id == "files" }) else {
            return nil
        }

        filterIdentifier.withLock { $0 = files.id }

        return files.id
    }

    /// `milliseconds(since:)` is how long ago `start` was, in whole milliseconds, for the duration every line above carries.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
