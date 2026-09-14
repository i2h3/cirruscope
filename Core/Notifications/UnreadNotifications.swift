// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `UnreadNotifications` fetches the notifications the connected server still has queued for the user, and reports what that means for the app icon badge.
///
/// It is the one place the app asks a server how many notifications are unread, and it is deliberately stateless: it takes nothing but a reason to log the fetch under, resolves the account from `Keychain` itself, and answers with a value. That is what lets the iOS background refresh — which runs in a process with no store, no view hierarchy, and nothing restored but the Keychain — call exactly the code the foreground calls, instead of a second implementation free to drift from it.
/// Everything here is `nonisolated` and nothing it touches is main-actor-bound, which is the property the background path depends on; see AGENTS.md → Concurrency.
/// There is no read/unread flag on a Nextcloud notification: the server returns exactly the ones still queued, so their count *is* the unread count. macOS reads them the same way in `NotificationMonitor`.
enum UnreadNotifications {
    /// `Outcome` is the closed set of results a fetch can have, carrying the notifications themselves only in the one case where there are any to carry.
    enum Outcome: Sendable {
        /// `fetched` carries the notifications currently queued, which is the empty array when there are none.
        case fetched([NotificationItem])

        /// `noAccount` reports that no usable credentials are stored, so there is no server to ask.
        case noAccount

        /// `endpointUnavailable` reports the `404` an instance answers while its notifications app is absent or disabled.
        case endpointUnavailable

        /// `credentialsRejected` reports that the stored app password was refused, so it has been revoked on the server.
        case credentialsRejected

        /// `cancelled` reports that the fetch was cancelled before it finished, which is what a background task running out of its allotted time looks like from in here.
        case cancelled

        /// `unreachable` reports every other failure, all of which are treated as transient.
        case unreachable

        /// `badgeUpdate` is what this outcome means for the app icon badge.
        ///
        /// Deciding it here rather than at whichever call site happens to write the badge is what keeps the foreground and the background path from reaching different conclusions about the same answer, and it is the whole of the feature's logic that can be tested without a server.
        /// An outcome that learned nothing leaves the badge alone: a blocked request, a captive portal, or a background run that ran out of time must not read to the user as "everything was read". An outcome that learned there is nothing to count clears it, which covers a signed-out app, a revoked app password, and an instance whose notifications app was switched off.
        var badgeUpdate: BadgeUpdate {
            switch self {
                case let .fetched(items):
                    UnreadNotifications.badgeUpdate(forFetchedCount: items.count)

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

    /// `badgeUpdate(forFetchedCount:)` is what a fetch that reached the server means for the badge: show exactly what it found.
    ///
    /// It is a function of its own rather than a line inside `Outcome.badgeUpdate` so that it can be tested. Neither test target links Rainmaker — `ServerAddressEndpointDerivationTests` says so and works around it the same way — so a test can name `Outcome` but cannot build a `NotificationItem` to put in its `fetched` case, and this is the half of that mapping which actually has a rule in it.
    /// Nothing is clamped here. A count comes from an array and cannot be negative, and the lower bound `setBadgeCount(_:)` insists on belongs with the call that would fail without it.
    static func badgeUpdate(forFetchedCount count: Int) -> BadgeUpdate {
        .set(count)
    }

    /// `fetch(reason:)` asks the connected server for the notifications queued for the user, reporting what came back.
    ///
    /// `reason` names which half of the app asked — `"foreground"` or `"background"` — and appears in every line this logs, because the two can overlap: a background run started while the app was away is still in flight when the user brings the app back and the foreground refresh begins beside it. A `StaticString` is used so the value prints in the clear in the log store rather than as `<private>`.
    /// The account is resolved through `Keychain.accounts().first`, exactly as `Store.restored()` resolves it, rather than taken as a parameter. That is not indirection for its own sake: the background path has no store to ask, a `Rainmaker.Server` is then built and used entirely inside this one function so it never crosses an isolation boundary, and the foreground path pays one Keychain read to be provably running the same code.
    /// It never throws. Every failure is a case of `Outcome`, because both callers want to decide what a failure means for the badge rather than to handle an error.
    static func fetch(reason: StaticString) async -> Outcome {
        let started = ContinuousClock.now

        logger.notice("Fetching unread notifications (\(reason))")

        guard let account = Keychain.accounts().first else {
            logger.notice("No account is configured, so there is nothing to fetch (\(reason))")
            return .noAccount
        }

        guard let server = ServerConnection.authenticated(address: account.server) else {
            logger.notice("No credentials are stored for the configured account, so there is nothing to fetch (\(reason))")
            return .noAccount
        }

        do {
            let items = try await server.notifications()
            logger.notice("Fetched \(items.count, privacy: .public) unread notification(s) in \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .fetched(items)
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
            logger.notice("The stored app password was rejected after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason))")
            return .credentialsRejected
        } catch {
            logger.notice("Could not fetch unread notifications after \(Self.milliseconds(since: started), privacy: .public) ms (\(reason)): \(error.localizedDescription)")
            return .unreachable
        }
    }

    /// `milliseconds(since:)` is how long ago `start` was, in whole milliseconds, for the duration every line above carries.
    ///
    /// A monotonic clock rather than a `Date` difference, because a background run can straddle a wall-clock adjustment, and an integer rather than `Duration`'s own description so it prints in the clear without being marked public by hand.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
