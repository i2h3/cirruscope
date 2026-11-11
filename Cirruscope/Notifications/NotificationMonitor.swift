// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Observation
import os
import Rainmaker

/// `NotificationMonitor` watches the connected server's notifications while the app is in front of the user, keeping the unread count, the app icon badge and Notification Center in step with them.
@Observable
@MainActor
final class NotificationMonitor {
    /// `notifications` is what the server last listed as queued for the user, for as long as the monitor watches its account.
    private(set) var notifications: [ServerNotificationTransferObject] = []

    /// `unreadCount` is how many notifications the server has queued for the user, derived so it cannot disagree with the list it counts.
    ///
    /// There is no read/unread flag on a Nextcloud notification: the server returns exactly the pending ones.
    var unreadCount: Int {
        notifications.count
    }

    /// `logger` records monitoring activity under the `NotificationMonitor` category.
    let logger = Logger(for: NotificationMonitor.self)

    /// `writeBadge` applies one decision about the app icon badge, the Dock's on the Mac and the home screen's on the iPhone.
    private let writeBadge: @MainActor (UnreadNotifications.BadgeUpdate) async -> Void

    /// `mayPost` answers whether new notifications may be posted right now, rather than only recorded as seen.
    private let mayPost: @MainActor () -> Bool

    /// `account` is the account being watched, or `nil` while the monitor is stopped.
    @ObservationIgnored
    private var account: ServerAccount?

    /// `onCredentialsRejected` is what the server refusing `account`'s app password leads to, supplied by whoever started the monitor.
    @ObservationIgnored
    private var onCredentialsRejected: (@MainActor (ServerAccount) -> Void)?

    /// `streamTask` consumes the server's event stream, and is cancelled by `suspend()` and `stop()`.
    @ObservationIgnored
    private var streamTask: Task<Void, Never>?

    /// `passTask` runs the fetch under way and any fetch requested while it ran, and is cancelled with the stream.
    @ObservationIgnored
    private var passTask: Task<Void, Never>?

    /// `gate` keeps fetches from overlapping and ties each to the session it was requested in.
    @ObservationIgnored
    private var gate = NotificationRefreshGate()

    /// `isSuspended` is whether the monitor keeps its account but neither streams nor fetches, while the iPhone app is in the background or after a refusal it has not confirmed.
    @ObservationIgnored
    private var isSuspended = false

    /// `endpointUnavailable` is set once the server reports its notifications app absent, so the monitor stops fetching on every event until the stream connects again or the monitor is started again.
    @ObservationIgnored
    private var endpointUnavailable = false

    /// `lastBadge` is the badge decision written last, so an unchanged one is not written again on every pass.
    @ObservationIgnored
    private var lastBadge: UnreadNotifications.BadgeUpdate?

    /// `init(writeBadge:mayPost:)` builds a monitor writing the badge through `writeBadge` and posting only while `mayPost` answers `true`.
    init(writeBadge: @escaping @MainActor (UnreadNotifications.BadgeUpdate) async -> Void, mayPost: @escaping @MainActor () -> Bool) {
        self.writeBadge = writeBadge
        self.mayPost = mayPost
    }

    /// `start(for:onCredentialsRejected:)` begins watching `account`, fetching at once and then on every change the server reports, and calls `onCredentialsRejected` should the server refuse the account's app password.
    func start(for account: ServerAccount, onCredentialsRejected: @escaping @MainActor (ServerAccount) -> Void) {
        self.onCredentialsRejected = onCredentialsRejected

        if account == self.account, streamTask != nil, isSuspended == false {
            logger.notice("Already watching this account; fetching once more")
            endpointUnavailable = false
            lastBadge = nil
            requestRefresh(routine: false)
            return
        }

        if account != self.account {
            notifications = []
        }

        gate.advance()
        streamTask?.cancel()
        passTask?.cancel()
        passTask = nil
        self.account = account
        isSuspended = false
        endpointUnavailable = false
        lastBadge = nil

        logger.notice("Starting the notification monitor")

        Task {
            await NotificationAuthorization.requestIfUndetermined(reason: "monitor")
        }

        let server = ServerConnection.authenticated(account)
        let generation = gate.generation

        streamTask = Task {
            await self.consume(server, generation: generation)
        }
    }

    /// `suspend()` stops streaming and fetching but keeps the account, its refusal handler and the last list, for the iPhone app going to the background and for a refusal that has not been confirmed.
    func suspend() {
        gate.advance()
        streamTask?.cancel()
        streamTask = nil
        passTask?.cancel()
        passTask = nil
        isSuspended = true
        lastBadge = nil
        logger.notice("Suspended the notification monitor")
    }

    /// `stop()` ends watching, forgets the account and the list, and clears the badge.
    ///
    /// Every sign-out calls it, and so does the Mac whenever the server becomes unusable — unsupported, unreachable, or without a notifications app.
    func stop() {
        gate.advance()
        streamTask?.cancel()
        streamTask = nil
        passTask?.cancel()
        passTask = nil
        account = nil
        onCredentialsRejected = nil
        isSuspended = false
        endpointUnavailable = false
        notifications = []
        logger.notice("Stopped the notification monitor")

        guard lastBadge != .clear else {
            return
        }

        lastBadge = .clear

        Task {
            await writeBadge(.clear)
        }
    }

    /// `refreshNow()` fetches once more, which the Mac asks for whenever the app becomes active and the iPhone whenever Nextcloud's notifications panel closes.
    ///
    /// It does nothing while the monitor is stopped or suspended.
    func refreshNow() {
        requestRefresh(routine: false)
    }

    /// `published(after:current:)` is the list to publish once a fetch came to `outcome`, `current` being the list published before.
    ///
    /// Only an answer from the server replaces it; a fetch that learned nothing keeps it, since a network blip must not read as "everything was read".
    nonisolated static func published(after outcome: UnreadNotifications.Outcome, current: [ServerNotificationTransferObject]) -> [ServerNotificationTransferObject] {
        switch outcome {
            case let .fetched(items, _):
                items

            case .noAccount, .endpointUnavailable, .credentialsRejected:
                []

            case .cancelled, .unreachable:
                current
        }
    }

    /// `consume(_:generation:)` reads the server's event stream for the session `generation` names, requesting a fetch whenever it connects or reports a change.
    ///
    /// The stream connecting is also when the notifications app may have come back, so the latch set when it was missing is cleared then.
    /// A refusal the stream itself reports goes the way a refused fetch does, once it is known to belong to the session still running.
    private func consume(_ server: Server, generation: UInt64) async {
        do {
            for try await event in server.events([.notifications]) {
                guard generation == gate.generation else {
                    return
                }

                switch event {
                    case .connected:
                        endpointUnavailable = false
                        requestRefresh(routine: false)

                    case .notifications:
                        requestRefresh(routine: true)

                    default:
                        break
                }
            }

            guard generation == gate.generation else {
                return
            }

            logger.notice("The notification stream ended")
            streamTask = nil
        } catch is CancellationError {
            // Expected when `suspend()` or `stop()` cancels the task; nothing to do.
        } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
            guard generation == gate.generation, let account else {
                return
            }

            logger.notice("The notification stream was refused the app password")
            refuse(account, generation: generation)
        } catch {
            guard generation == gate.generation else {
                return
            }

            logger.error("The notification stream ended: \(error.localizedDescription, privacy: .public)")
            streamTask = nil
        }
    }

    /// `requestRefresh(routine:)` starts a fetch, or owes one more after the fetch under way, unless the monitor is stopped, suspended or knows the notifications app is missing.
    private func requestRefresh(routine: Bool) {
        guard account != nil else {
            return
        }

        guard isSuspended == false else {
            return
        }

        guard endpointUnavailable == false else {
            logger.debug("Not fetching: the notifications app was found missing")
            return
        }

        guard gate.request() else {
            logger.debug("A fetch is under way; one more is owed after it")
            return
        }

        let generation = gate.generation

        passTask = Task {
            await self.runPasses(generation: generation, routine: routine)
        }
    }

    /// `runPasses(generation:routine:)` runs one fetch, and another for as long as one was requested while the last ran.
    private func runPasses(generation: UInt64, routine: Bool) async {
        var routine = routine

        repeat {
            await runOnePass(generation: generation, routine: routine)
            routine = true
        } while gate.finish(generation)
    }

    /// `runOnePass(generation:routine:)` fetches the notifications once, hands the answer to `ServerNotificationDispatcher`, and adopts it if that admitted it.
    private func runOnePass(generation: UInt64, routine: Bool) async {
        guard generation == gate.generation, let account else {
            return
        }

        guard isSuspended == false, endpointUnavailable == false else {
            return
        }

        let ticket = ServerNotificationDispatcher.issueTicket()
        let outcome = await UnreadNotifications.fetch(as: account, reason: "monitor", routine: routine)

        guard generation == gate.generation else {
            return
        }

        let delivery = await ServerNotificationDispatcher.deliver(outcome, ticket: ticket, mayPost: mayPost(), reason: "monitor", routine: routine)

        guard generation == gate.generation, delivery == .adopted else {
            return
        }

        notifications = Self.published(after: outcome, current: notifications)
        await write(delivery.badgeUpdate(for: outcome))

        guard generation == gate.generation else {
            return
        }

        switch outcome {
            case .endpointUnavailable:
                logger.notice("The notifications app is missing; not fetching again until the stream connects again")
                endpointUnavailable = true

            case .credentialsRejected:
                logger.notice("A fetch was refused the app password")
                refuse(account, generation: generation)

            default:
                break
        }
    }

    /// `refuse(_:generation:)` acts on the server refusing `account`'s app password in the session `generation` names: it clears the list and the badge, suspends the monitor, and calls the refusal handler.
    ///
    /// The handler is called from a task of its own, so whatever it does — the Mac presents an alert and a sign-in window — runs with nothing of this monitor on the stack, and only if the monitor still watches the account by then: a sign-out in between has stopped it, and a refusal of an account nobody is signed in to any more leads nowhere.
    private func refuse(_ account: ServerAccount, generation: UInt64) {
        guard generation == gate.generation else {
            return
        }

        let handler = onCredentialsRejected

        notifications = []
        suspend()

        Task {
            await self.write(.clear)
        }

        Task { @MainActor in
            guard self.account == account else {
                self.logger.notice("The monitor stopped watching the refused account before the refusal could be handled; ignoring it")
                return
            }

            handler?(account)
        }
    }

    /// `write(_:)` applies `update` to the badge, unless it leaves the badge unchanged or repeats the decision written last.
    private func write(_ update: UnreadNotifications.BadgeUpdate) async {
        guard update != .unchanged, update != lastBadge else {
            return
        }

        lastBadge = update
        await writeBadge(update)
    }
}
