// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WidgetKit

/// `ActivityEntry` is one thing the activity widget can be drawn as: a feed, or one of the states a feed cannot be.
///
/// The states are not error handling bolted onto a list. A widget sits on a Home Screen for days without anybody opening the app behind it, so what it says when it cannot show a feed is most of what it ever says, and each of these means something different to whoever glances at it. An empty feed and an unreachable server in particular must never look alike: one reports that nothing happened, the other that nobody knows.
struct ActivityEntry: TimelineEntry {
    /// `Content` is what the widget has to draw.
    enum Content: Equatable, Sendable {
        /// `feed` carries rows to draw, which is what a reachable server with file activity produces.
        case feed([ActivityRow])

        /// `empty` is a server that answered with no activity at all — the design's "All quiet", and a success rather than a failure.
        case empty

        /// `notSignedIn` is a widget added before an account was connected, or left behind after a sign-out.
        case notSignedIn

        /// `unavailable` is an instance whose activity app is absent or switched off, so there is nothing to show and nothing the user can do about it from here.
        case unavailable

        /// `redacted` is the first render and the redacted state the system asks for, which is drawn as bars rather than as text nobody should read as real.
        case redacted
    }

    /// `date` is when WidgetKit should display this entry, which `TimelineEntry` requires.
    let date: Date

    /// `content` is what to draw.
    let content: Content

    /// `fetchedAt` is when the rows in `content` were actually read from the server, which is not `date` for a stale entry and is what the stale footer counts from.
    let fetchedAt: Date?

    /// `isStale` marks rows that were carried over from an earlier fetch because the newest one failed.
    ///
    /// It is kept separate from `content` rather than made a case of it so that the feed is drawn by one piece of code either way, dimmed and footnoted rather than re-laid-out. The design asks for exactly that: the same rows, at reduced opacity, under a line saying when they were true.
    let isStale: Bool

    /// `init(date:content:fetchedAt:isStale:)` builds an entry, defaulting the two things only a feed ever carries.
    init(date: Date, content: Content, fetchedAt: Date? = nil, isStale: Bool = false) {
        self.date = date
        self.content = content
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }
}
