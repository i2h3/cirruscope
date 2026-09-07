// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import BackgroundTasks
import Foundation
import os

///
/// The background job iOS wakes the app for, which fetches the unread notification count, writes it to the app icon badge, and stops.
///
/// The scope is the design. A background launch gets a short, unpredictable slice of time on a schedule nobody can force, with no debugger attached and no user watching, so everything the app could do while awake and does not do here is one less thing that can fail invisibly: nothing is persisted, no icon is downloaded, no web view is built, no store is touched. What is left is one HTTP GET and one integer.
/// Registration is SwiftUI's. `iOSApp` carries `.backgroundTask(.appRefresh(_:))`, which registers this identifier with `BGTaskScheduler` while the scene is being built — inside launch, which is the deadline registration has — and which also owns the expiration handler and the completion call that the manual `BGTaskScheduler.register` API leaves to its caller. Submitting the requests is not SwiftUI's, and that is what `submitRequest(reason:)` is for.
/// Everything here logs at `.notice` or above, because `.debug` and `.info` are ephemeral and a run nobody watched leaves nothing else behind. See AGENTS.md → Logging and Diagnostics.
///
enum NotificationRefreshTask {
    ///
    /// Property list keys.
    ///
    private enum InfoPlistKey {
        ///
        /// Property list key.
        ///
        static let identifier = "NotificationRefreshTaskIdentifier"
    }

    ///
    /// Records every request submitted, withdrawn, or found pending, and every run from end to end, under the `NotificationRefreshTask` category.
    ///
    static let logger = Logger(for: NotificationRefreshTask.self)

    ///
    /// How soon after a submission the system may start the task at the earliest, in seconds.
    ///
    /// Fifteen minutes is a floor and not a schedule. The system decides when — or whether — to run the task at all, from the user's own habits, the battery, and Low Power Mode, and the only thing this value does is refuse anything sooner. It is deliberately not shorter: asking more often than the server's state meaningfully changes spends the app's background budget without changing the badge.
    ///
    static let earliestInterval: TimeInterval = 15 * 60

    ///
    /// The identifier both the property list and `BGTaskScheduler` know this task by.
    ///
    /// Read from the property list rather than hardcoded for the same reason `AppGroup.identifier` is: it derives from the bundle identifier, which is a brandable value differing between builds. The property list names it twice — here, and in `BGTaskSchedulerPermittedIdentifiers` — from one build setting, because a disagreement between those two is invisible at build time and surfaces only much later, as a submission failing with a permission error nobody was watching for.
    /// Trapping on a missing entry is deliberate and matches the house pattern. This is read while the scene is being built, so a build configured without it fails during launch, and the iOS test action launches the app — which turns a misconfiguration into a test failure here rather than into a fork's crash later.
    ///
    static let identifier: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.identifier) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.identifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.identifier)\" must be a string but was \(value).")
        }

        return stringValue
    }()

    ///
    /// Run one background refresh.
    ///
    /// A run is identified in the log by the process it ran in and a four-digit number drawn once at its start. The process identifier alone is not enough — a wake-up can be delivered to a process that is merely suspended rather than gone, so two runs can share one — and a counter is no better, since each background launch would start it at one again. A random number needs no shared state to maintain, prints in the clear where a string would be redacted, and is enough to pull one run out of an interleaved log by eye.
    /// The next request is submitted before any work is done, not after. An expiration, a throw, or a crash below must not cost the app its next wake-up, because an app with no pending request is never woken again, and that is the one way this feature dies without leaving a trace. The cost of getting it wrong the other way is one wasted round trip to the scheduler when the account turns out to be gone, which the branch below then withdraws.
    /// Cancellation is how expiration arrives: SwiftUI cancels the task this body runs in, so the fetch unwinds as cancelled and the badge is left alone. It is logged as an error because a run that keeps running out of time is exactly the thing worth finding in a log a week later.
    ///
    static func run() async {
        let started = ContinuousClock.now
        let processID = ProcessInfo.processInfo.processIdentifier
        let runID = UInt32.random(in: 1000 ... 9999)

        logger.notice("Background refresh started (pid \(processID, privacy: .public), run \(runID, privacy: .public))")

        submitRequest(reason: "re-arm")

        await AppIconBadge.logAuthorizationState()

        let outcome = await UnreadNotifications.fetch(reason: "background")
        await AppIconBadge.apply(outcome.badgeUpdate)

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

    ///
    /// Ask the system to wake the app for another refresh, replacing any request already pending.
    ///
    /// `reason` names which moment asked — a scene-phase change, a sign-in, or a run re-arming itself — because a submission that never happened and a submission that failed look identical in a log unless both are written down. Submitting while a request for the same identifier is still pending is neither an error nor a duplicate: the scheduler replaces the earlier one, which is what makes calling this from several places safe rather than merely tolerable.
    /// The failure is logged from the `NSError` rather than from a typed case, so the domain and the numeric code are on the record whatever the importer called them. Those numbers are the whole diagnosis, which is why `explanation(of:)` puts them in words as well.
    ///
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

    ///
    /// Withdraw any pending request, so the system stops waking the app for work it no longer has.
    ///
    static func cancelRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        logger.notice("Withdrew the pending background refresh request for \(identifier, privacy: .public)")
    }

    ///
    /// Record whether the app is actually armed.
    ///
    /// This is the line that separates a system which never ran the task from an app which never asked it to, and there is no other way to tell those two apart after the fact — the first is the scheduler's judgement and nothing to fix, the second is a bug. It is called on arriving in the foreground rather than on the way out, because an unstructured task started while the app is being suspended is not guaranteed to run at all.
    ///
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

    ///
    /// What one submission failure means in words, so the log names the cause instead of only numbering it.
    ///
    /// The codes are `BGTaskScheduler.Error.Code`'s, matched numerically so an unrecognized one still reads as something rather than as nothing.
    ///
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

    ///
    /// How long ago `start` was, in whole milliseconds.
    ///
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }
}
