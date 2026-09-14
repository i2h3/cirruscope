// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `RecentActivity` fetches the newest file activity of the connected server, prepared for a widget to draw.
///
/// It is the sibling of `UnreadNotifications` and deliberately the same shape: stateless, resolving the account from `Keychain` itself rather than taking one, and answering with a value instead of throwing. That is what lets a widget timeline provider — a short-lived process with no store, no view hierarchy and nothing restored but the Keychain — call exactly the code an app would.
/// Everything here is `nonisolated` and nothing it touches is main-actor-bound, which is the property an extension depends on; see AGENTS.md → Concurrency.
/// Scope is the server's own `files` filter rather than a client-side selection, so an instance decides what counts as file activity. That filter is Nextcloud's `FileChanges`, which admits `file_created`, `file_changed`, `file_deleted` and `file_restored` and excludes sharing entirely — see `DECISIONS.md` for why the widget shows no shares.
enum RecentActivity {
    /// `Outcome` is the closed set of results a fetch can have, carrying the prepared rows only in the one case where there are any to carry.
    enum Outcome: Sendable {
        /// `fetched` carries the rows to draw, which is the empty array when the server has nothing to report — the widget's "All quiet", which is a success rather than a failure.
        case fetched([ActivityRow])

        /// `noAccount` reports that no usable credentials are stored, so there is no server to ask.
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
    ///
    /// `reason` names which surface asked and appears in every line this logs, as it does in `UnreadNotifications`, because a widget refresh and an app refresh can be in flight together. A `StaticString` is used so the value prints in the clear rather than as `<private>`.
    /// `limit` is what the server is asked for, not what comes back: an activity whose type is none of the four the badges cover is dropped by `ActivityRow`, so a caller wanting *n* rows should ask for more than *n*. The server clamps it to `1...200` regardless.
    /// It never throws. Every failure is a case of `Outcome`, because the caller wants to decide what a failure means for what is already on screen rather than to handle an error.
    static func fetch(limit: Int, reason: StaticString) async -> Outcome {
        let started = ContinuousClock.now

        logger.notice("Fetching recent activity (\(reason))")

        guard let account = Keychain.accounts().first else {
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

            return .fetched(rows)
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
    ///
    /// The filter is matched by id rather than by name, the name being localized into the account's language while the id is not. `ActivityFilter.object` is excluded even though the files app is what registers it: it is the placeholder id an object-scoped query uses, not a filter a caller may pass on its own.
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
    ///
    /// A monotonic clock rather than a `Date` difference, and an integer rather than `Duration`'s own description so it prints in the clear without being marked public by hand — the same reasoning as in `UnreadNotifications`.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
