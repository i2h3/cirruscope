// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// Decides when to ask for an App Store rating: after enough days of use, at most once per version, and never on the first activation of a process.
///
enum ReviewRequest {
    private static let logger = Logger(for: ReviewRequest.self)

    ///
    /// The days of use before the first request, and again between two requests.
    ///
    static let requiredDaysOfUse = 4

    ///
    /// The defaults keys the count of days, the last day and the last requested version are stored under.
    ///
    private enum Key {
        static let lastDayOfUse = "ReviewRequestLastDayOfUse"
        static let daysOfUse = "ReviewRequestDaysOfUse"
        static let lastRequestedVersion = "ReviewRequestLastRequestedVersion"
    }

    @MainActor
    private static var hasSeenActivation = false

    ///
    /// Answers whether to ask for a rating on this activation, counting a day of use when the app is `inUse`.
    ///
    /// The first activation of a process, the one launch brings, never asks, whether or not the app is in use by then, so callers report every activation rather than only those in use.
    ///
    @MainActor
    static func isDueOnActivation(inUse: Bool) -> Bool {
        let isFirstActivation = hasSeenActivation == false
        hasSeenActivation = true

        guard inUse else {
            return false
        }

        recordDayOfUse()

        guard isFirstActivation == false else {
            logger.debug("Not asking for a review on the first activation of this process")
            return false
        }

        return claim()
    }

    ///
    /// Counts the day `now` falls on as a day of use, at most once per calendar day.
    ///
    static func recordDayOfUse(now: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        if let lastDay = defaults.object(forKey: Key.lastDayOfUse) as? Date, calendar.isDate(lastDay, inSameDayAs: now) {
            return
        }

        let daysOfUse = defaults.integer(forKey: Key.daysOfUse) + 1
        defaults.set(now, forKey: Key.lastDayOfUse)
        defaults.set(daysOfUse, forKey: Key.daysOfUse)
        logger.notice("Counted day of use \(daysOfUse, privacy: .public)")
    }

    ///
    /// Answers whether a rating is due for `version` and, when it is, records the request, so the next one waits for another version and another `requiredDaysOfUse` days of use.
    ///
    static func claim(version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, defaults: UserDefaults = .standard) -> Bool {
        guard let version else {
            logger.error("Not asking for a review: the app's version is unknown")
            return false
        }

        let daysOfUse = defaults.integer(forKey: Key.daysOfUse)

        guard daysOfUse >= requiredDaysOfUse else {
            logger.debug("Not asking for a review after \(daysOfUse, privacy: .public) of \(requiredDaysOfUse, privacy: .public) days of use")
            return false
        }

        guard defaults.string(forKey: Key.lastRequestedVersion) != version else {
            logger.debug("Not asking for a review: version \(version, privacy: .public) was asked about already")
            return false
        }

        defaults.set(version, forKey: Key.lastRequestedVersion)
        defaults.set(0, forKey: Key.daysOfUse)
        logger.notice("Asking for a review of version \(version, privacy: .public) after \(daysOfUse, privacy: .public) days of use")
        return true
    }
}
