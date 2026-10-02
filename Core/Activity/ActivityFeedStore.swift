// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `ActivityFeedStore` keeps the last activity a fetch succeeded in reading, so a refresh that fails has something to show instead of nothing.
///
/// A widget is redrawn by a process that does not outlive the drawing, so "what we had last time" cannot be a property on a timeline provider: the next refresh runs somewhere else entirely and starts with nothing. It lives in the shared App Group container instead, beside the cached assets, which is the one place both the apps and the extension can reach.
/// The point is the widget's stale state. A server that cannot be reached must leave the rows it last had on screen, dimmed and dated, rather than blanking them — an empty widget reads as "nothing happened", which is a different and wrong statement.
enum ActivityFeedStore {
    /// `Snapshot` is one successful fetch: the rows it produced, and when it happened.
    struct Snapshot: Codable, Sendable {
        /// `rows` are the rows that fetch produced, in the order the server gave them.
        let rows: [ActivityRow]

        /// `fetchedAt` is when the fetch returned, which the stale state renders as how long ago the rows were true.
        let fetchedAt: Date
    }

    /// `logger` records reads and writes under the `ActivityFeedStore` category.
    private static let logger = Logger(for: ActivityFeedStore.self)

    /// `fileName` is what the snapshot is stored as inside the container.
    private static let fileName = "ActivityFeed.json"

    /// `fileURL` is where the snapshot lives, at the root of the App Group container.
    private static var fileURL: URL {
        AppGroup.containerURL.appending(component: fileName, directoryHint: .notDirectory)
    }

    /// `save(rows:fetchedAt:)` records a successful fetch, replacing whatever was there.
    ///
    /// Failures are logged and swallowed. Nothing a widget draws is worth failing a refresh over, and the consequence of not writing is only that a later failure has no rows to fall back on.
    static func save(rows: [ActivityRow], fetchedAt: Date) {
        do {
            try JSONEncoder().encode(Snapshot(rows: rows, fetchedAt: fetchedAt)).write(to: fileURL, options: .atomic)
            logger.debug("Saved \(rows.count, privacy: .public) activity row(s)")
        } catch {
            logger.error("Could not save the activity feed: \(error.localizedDescription)")
        }
    }

    /// `load()` is the last successful fetch, or `nil` when there is none to read.
    ///
    /// A snapshot that cannot be decoded is treated as absent rather than as an error: the shape it was written in may have changed between releases, and a widget that has no stale state to show is a far better outcome than one that refuses to draw.
    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            logger.notice("The saved activity feed could not be decoded and is being ignored")
            return nil
        }

        return snapshot
    }

    /// `clear()` forgets the saved feed.
    ///
    /// Every sign-out runs it beside the caches describing the same server, because these rows name the files and the people of the server being signed out of.
    /// The widget runs it too whenever the Keychain says nobody is signed in, the server rejects the stored app password, or the account it fetched for signed out while it was fetching, because a timeline already under way during a sign-out can save its rows after the app has cleared them.
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
