// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import BackgroundTasks
import Foundation
import os

/// The background job iOS wakes the app for, which fetches the notifications the server has queued, posts the new ones to Notification Center, withdraws those the server no longer lists, writes the count to the app icon badge, and stops.
enum NotificationRefreshTask {
    /// Property list keys.
    private enum InfoPlistKey {
        /// Property list key.
        static let identifier = "NotificationRefreshTaskIdentifier"
    }

    /// Records every request submitted, withdrawn, or found pending, and every run from end to end, under the `NotificationRefreshTask` category.
    static let logger = Logger(for: NotificationRefreshTask.self)

    /// How soon after a submission the system may start the task at the earliest, in seconds.
    ///
    /// Fifteen minutes is a floor and not a schedule. The system decides when — or whether — to run the task at all, from the user's own habits, the battery, and Low Power Mode, and the only thing this value does is refuse anything sooner. It is deliberately not shorter: asking more often than the server's state meaningfully changes spends the app's background budget without changing the badge.
    static let earliestInterval: TimeInterval = 15 * 60

    /// The identifier both the property list and `BGTaskScheduler` know this task by.
    static let identifier: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.identifier) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.identifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.identifier)\" must be a string but was \(value).")
        }

        return stringValue
    }()

    /// Run one background refresh.
    static func run() async {
        let started = ContinuousClock.now
        let processID = ProcessInfo.processInfo.processIdentifier
        let runID = UInt32.random(in: 1000 ... 9999)

        logger.notice("Background refresh started (pid \(processID, privacy: .public), run \(runID, privacy: .public))")

        submitRequest(reason: "re-arm")

        await NotificationAuthorization.logState(reason: "background")

        let ticket = ServerNotificationDispatcher.issueTicket()
        let outcome = await UnreadNotifications.fetch(reason: "background")
        let delivery = await ServerNotificationDispatcher.deliver(outcome, ticket: ticket, mayPost: true, reason: "background", routine: false)

        await AppIconBadge.apply(delivery.badgeUpdate(for: outcome))

        switch outcome {
            case .noAccount, .credentialsRejected:
                cancelRequest()

            default:
                break
        }

        if Task.isCancelled {
            logger.error("Background refresh ran out of its allotted time and was cancelled (pid \(processID, privacy: .public), run \(runID, privacy: .public))")
        }

        logger.notice("Background refresh finished after \(Self.milliseconds(since: started), privacy: .public) ms (pid \(processID, privacy: .public), run \(runID, privacy: .public))")
    }

    /// Ask the system to wake the app for another refresh, replacing any request already pending.
    static func submitRequest(reason: StaticString) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)

        logger.debug("Submitting a background refresh request (\(reason))")

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("Submitted a background refresh request for \(identifier, privacy: .public) to start no earlier than \(Int(Self.earliestInterval), privacy: .public) s from now (\(reason))")
        } catch {
            let failure = error as NSError
            logger.error("Could not submit a background refresh request for \(identifier, privacy: .public) (\(reason)): \(Self.explanation(of: failure)) — domain \(failure.domain, privacy: .public), code \(failure.code, privacy: .public)")
        }
    }

    /// Withdraw any pending request, so the system stops waking the app for work it no longer has.
    static func cancelRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        logger.notice("Withdrew the pending background refresh request for \(identifier, privacy: .public)")
    }

    /// Record whether the app is actually armed.
    ///
    /// This is the line that separates a system which never ran the task from an app which never asked it to, and there is no other way to tell those two apart after the fact — the first is the scheduler's judgement and nothing to fix, the second is a bug. It is called on arriving in the foreground rather than on the way out, because an unstructured task started while the app is being suspended is not guaranteed to run at all.
    static func logPendingRequests() async {
        let requests = await BGTaskScheduler.shared.pendingTaskRequests()

        guard requests.isEmpty == false else {
            logger.notice("No background refresh request is pending")
            return
        }

        for request in requests {
            let seconds = Int(request.earliestBeginDate?.timeIntervalSinceNow ?? 0)
            logger.notice("A background refresh request for \(request.identifier, privacy: .public) is pending, to start no earlier than \(seconds, privacy: .public) s from now")
        }
    }

    /// What one submission failure means in words, so the log names the cause instead of only numbering it.
    private static func explanation(of error: NSError) -> StaticString {
        guard error.domain == BGTaskScheduler.errorDomain else {
            return "an error from outside the task scheduler"
        }

        switch error.code {
            case 1:
                return "background refresh is unavailable, which the Simulator and a device with Background App Refresh switched off both report"

            case 2:
                return "too many task requests are already pending"

            case 3:
                return "the app is not permitted to schedule it, which a missing UIBackgroundModes entry, an identifier absent from BGTaskSchedulerPermittedIdentifiers, and a user who has denied this app background launches all report"

            default:
                return "an unrecognized scheduler failure"
        }
    }

    /// How long ago `start` was, in whole milliseconds.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
