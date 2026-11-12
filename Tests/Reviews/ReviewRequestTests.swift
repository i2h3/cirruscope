// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ReviewRequestTests` pins when the app may ask for an App Store rating, after enough days of use and once per version, because a mistake there either nags people or never asks at all (issue #96).
///
struct ReviewRequestTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    ///
    /// Midday of the given day after the reference date, so neighbouring days never share a calendar day.
    ///
    private func day(_ number: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(number) * 86400 + 43200)
    }

    ///
    /// Runs `body` against a defaults domain of its own and removes it afterwards, so no case touches `UserDefaults.standard`.
    ///
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "ReviewRequestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func use(days: ClosedRange<Int>, _ defaults: UserDefaults) {
        for number in days {
            ReviewRequest.recordDayOfUse(now: day(number), calendar: calendar, defaults: defaults)
        }
    }

    @Test
    func `No rating is asked for before enough days of use`() throws {
        try withDefaults { defaults in
            use(days: 1 ... ReviewRequest.requiredDaysOfUse - 1, defaults)

            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults) == false)
        }
    }

    @Test
    func `Several activations on one day count as one day of use`() throws {
        try withDefaults { defaults in
            for hour in 0 ..< 10 {
                ReviewRequest.recordDayOfUse(now: day(1).addingTimeInterval(TimeInterval(hour) * 3600 - 43200), calendar: calendar, defaults: defaults)
            }

            use(days: 2 ... ReviewRequest.requiredDaysOfUse - 1, defaults)

            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults) == false)
        }
    }

    @Test
    func `A rating is asked for once enough days of use have passed, and only once per version`() throws {
        try withDefaults { defaults in
            use(days: 1 ... ReviewRequest.requiredDaysOfUse, defaults)

            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults))
            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults) == false)

            use(days: 100 ... 100 + ReviewRequest.requiredDaysOfUse, defaults)

            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults) == false)
        }
    }

    @Test
    func `A new version waits for another round of days of use`() throws {
        try withDefaults { defaults in
            use(days: 1 ... ReviewRequest.requiredDaysOfUse, defaults)
            #expect(ReviewRequest.claim(version: "1.0.0", defaults: defaults))

            use(days: 10 ... 10 + ReviewRequest.requiredDaysOfUse - 2, defaults)
            #expect(ReviewRequest.claim(version: "1.1.0", defaults: defaults) == false)

            use(days: 20 ... 20, defaults)
            #expect(ReviewRequest.claim(version: "1.1.0", defaults: defaults))
        }
    }

    @Test
    func `No rating is asked for when the version is unknown`() throws {
        try withDefaults { defaults in
            use(days: 1 ... ReviewRequest.requiredDaysOfUse, defaults)

            #expect(ReviewRequest.claim(version: nil, defaults: defaults) == false)
        }
    }
}
