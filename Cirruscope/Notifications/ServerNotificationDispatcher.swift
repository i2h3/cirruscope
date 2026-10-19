// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

///
/// `ServerNotificationDispatcher` acts on one fetch of the server's notifications in Notification Center: it admits the answer to the record, withdraws what the server no longer lists, and posts what is new.
///
/// Both apps' live monitors and the iPhone's background refresh hand their fetches here, so Notification Center follows one rule whoever fetched; it is the one caller of `UNUserNotificationCenter` for server notifications, through its async calls alone.
/// The record is written before anything is posted, so a run cut short after posting never posts the same notifications again, and each notification is posted only while its account is still signed in, a sign-out that lands in the middle of posting being taken back once posting ends.
/// Everything here is `nonisolated`, so the background refresh calls it without a hop, and nothing that is not `Sendable` crosses into or out of it.
/// It lives in `Cirruscope/` because the widget extension posts nothing.
///
enum ServerNotificationDispatcher {
    ///
    /// `Delivery` is what acting on one fetch came to, which decides whether the caller may adopt what it fetched.
    ///
    enum Delivery: Equatable, Sendable {
        ///
        /// `adopted` means the fetch was the latest and its account still signed in, so the caller may publish its count and act on its outcome.
        ///
        case adopted

        ///
        /// `superseded` means a later fetch was admitted first, so this one is stale.
        ///
        case superseded

        ///
        /// `notSignedIn` means the account the fetch was made as signed out before it could be acted on, or while it was.
        ///
        case notSignedIn

        ///
        /// `keychainUnreadable` means the Keychain refused to say who is signed in, so nothing was acted on.
        ///
        case keychainUnreadable

        ///
        /// `abandoned` means the task acting on the fetch was cancelled before anything was recorded.
        ///
        case abandoned

        ///
        /// `badgeUpdate(for:)` is what `outcome` means for the app icon badge once acting on it came to this: its own answer when adopted, and nothing otherwise.
        ///
        func badgeUpdate(for outcome: UnreadNotifications.Outcome) -> UnreadNotifications.BadgeUpdate {
            self == .adopted ? outcome.badgeUpdate : .unchanged
        }
    }

    ///
    /// `TicketUse` is how a fetch's outcome uses the ticket it took.
    ///
    enum TicketUse: Equatable, Sendable {
        ///
        /// `none` means the outcome learned nothing, so it claims no place in the order.
        ///
        case none

        ///
        /// `admit` means the outcome learned something without a listing to record, so it only claims its place.
        ///
        case admit

        ///
        /// `commit` means the outcome carries a listing, which is admitted to the record.
        ///
        case commit
    }

    ///
    /// `logger` records what every fetch did to Notification Center under the `ServerNotificationDispatcher` category.
    ///
    private static let logger = Logger(for: ServerNotificationDispatcher.self)

    ///
    /// `ticketUse(for:)` is how `outcome` uses its ticket.
    ///
    static func ticketUse(for outcome: UnreadNotifications.Outcome) -> TicketUse {
        switch outcome {
            case .fetched:
                .commit

            case .noAccount, .endpointUnavailable, .credentialsRejected:
                .admit

            case .cancelled, .unreachable:
                .none
        }
    }

    ///
    /// `takesBack(posted:admission:)` is whether the notifications just posted must be withdrawn again, given whether their account was still signed in once posting ended.
    ///
    /// A Keychain that cannot be read says nothing about a sign-out, so it takes nothing back.
    ///
    static func takesBack(posted: Int, admission: RefreshAdmission) -> Bool {
        posted > 0 && admission != .admitted && admission != .keychainUnreadable
    }

    ///
    /// `issueTicket()` takes the next place in the order of fetches, which a caller does before it fetches.
    ///
    static func issueTicket() -> ServerNotificationLedger.Ticket {
        ServerNotificationLedger.shared.issueTicket()
    }

    ///
    /// `deliver(_:ticket:mayPost:reason:routine:)` acts on `outcome`, fetched with `ticket`, in Notification Center, posting new notifications only if `mayPost`.
    ///
    /// `reason` names who fetched, as `UnreadNotifications` logs it, and `routine` moves the line a fetch that changed nothing writes to `.debug`.
    /// Cancellation is honoured before the record is written and not after: a background run expiring while it posts must not leave the record claiming what it never posted, and stopping between writing the record and posting would lose those notifications for good.
    ///
    static func deliver(_ outcome: UnreadNotifications.Outcome, ticket: ServerNotificationLedger.Ticket, mayPost: Bool, reason: StaticString, routine: Bool) async -> Delivery {
        let ledger = ServerNotificationLedger.shared

        switch ticketUse(for: outcome) {
            case .none:
                return .adopted

            case .admit:
                guard ledger.admit(ticket) else {
                    logger.notice("Turned away an outcome fetched with ticket \(ticket.value, privacy: .public), a later fetch having been admitted already (\(reason))")
                    return .superseded
                }

                return .adopted

            case .commit:
                break
        }

        guard case let .fetched(items, account) = outcome else {
            return .adopted
        }

        guard Task.isCancelled == false else {
            logger.notice("Abandoned the notifications fetched with ticket \(ticket.value, privacy: .public), the task having been cancelled (\(reason))")
            return .abandoned
        }

        let delivered = await deliveredServerNotifications()

        guard Task.isCancelled == false else {
            logger.notice("Abandoned the notifications fetched with ticket \(ticket.value, privacy: .public), the task having been cancelled (\(reason))")
            return .abandoned
        }

        let plan: ServerNotificationPlan

        switch ledger.commit(ticket, listing: items, account: account, delivered: delivered, mayPost: mayPost) {
            case let .admitted(admitted):
                plan = admitted

            case .superseded:
                return .superseded

            case .notSignedIn:
                return .notSignedIn

            case .keychainUnreadable:
                return .keychainUnreadable
        }

        withdraw(plan.withdraw)

        let posted = await post(plan.post, as: account, reason: reason)

        if takesBack(posted: posted.count, admission: ledger.admission(of: account)) {
            withdraw(Set(posted))
            ledger.clear(ifRecordedFor: ServerNotificationRecipient(account))
            logger.notice("The account signed out while its notifications were being posted; took back \(posted.count, privacy: .public) (\(reason))")
            return .notSignedIn
        }

        if plan.isBaseline {
            logger.notice("Recorded \(items.count, privacy: .public) notification(s) without posting any, as the first look at this account, and withdrew \(plan.withdraw.count, privacy: .public) (\(reason))")
        } else if mayPost == false {
            logger.log(level: routine && plan.withdraw.isEmpty ? .debug : .default, "Posting is withheld; withdrew \(plan.withdraw.count, privacy: .public) notification(s) (\(reason))")
        } else {
            logger.log(level: routine && posted.isEmpty && plan.withdraw.isEmpty ? .debug : .default, "Posted \(posted.count, privacy: .public) of \(plan.post.count, privacy: .public) new notification(s) and withdrew \(plan.withdraw.count, privacy: .public) (\(reason))")
        }

        return .adopted
    }

    ///
    /// `withdrawAll()` removes every notification the app has delivered or still has pending, which every sign-out does.
    ///
    /// Every one of them was about the account being signed out of — its server's notifications and, on the Mac, its web pages' messages and the files it downloaded — and one left in Notification Center would go on naming that account's people and files, and open its server's pages when tapped.
    ///
    static func withdrawAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        logger.notice("Withdrew every delivered and pending notification")
    }

    ///
    /// `deliveredServerNotifications()` is every server notification Notification Center currently holds.
    ///
    private static func deliveredServerNotifications() async -> [ServerNotificationPlan.Delivered] {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()

        return notifications.compactMap { notification in
            let request = notification.request

            return ServerNotificationContent.delivered(identifier: request.identifier, userInfo: ServerNotificationContent.strings(from: request.content.userInfo))
        }
    }

    ///
    /// `withdraw(_:)` removes the server notifications `ids` from Notification Center, delivered or pending.
    ///
    private static func withdraw(_ ids: Set<Int>) {
        guard ids.isEmpty == false else {
            return
        }

        let identifiers = ids.map { ServerNotificationContent.identifier(for: $0) }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    ///
    /// `post(_:as:reason:)` posts `items`, fetched as `account`, answering the identifiers of those it posted.
    ///
    /// Each is posted only while `account` is still signed in, and posting stops at the first the system refuses: the rest are recorded already, and trying them again on every fetch would only repeat the refusal.
    ///
    private static func post(_ items: [ServerNotificationTransferObject], as account: ServerAccount, reason: StaticString) async -> [Int] {
        let center = UNUserNotificationCenter.current()
        let recipient = ServerNotificationRecipient(account)
        var posted: [Int] = []

        for item in items {
            let admission = ServerNotificationLedger.shared.admission(of: account)

            guard admission == .admitted || admission == .keychainUnreadable else {
                logger.notice("Stopped posting after \(posted.count, privacy: .public) notification(s), the account having signed out (\(reason))")
                break
            }

            do {
                try await center.add(ServerNotificationContent.request(for: item, to: recipient))
                posted.append(item.id)
            } catch {
                let failure = error as NSError
                logger.error("Could not post notification \(item.id, privacy: .public): \(failure.localizedDescription, privacy: .public) — domain \(failure.domain, privacy: .public), code \(failure.code, privacy: .public) (\(reason))")
                break
            }
        }

        return posted
    }
}
