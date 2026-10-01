// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import WidgetKit

/// `ActivityTimelineProvider` decides what the activity widget shows and when WidgetKit should ask again.
///
/// It does the fetching through `RecentActivity`, which resolves the account from the Keychain itself, so nothing here needs an account passed in and the extension needs no store. What it adds on top is the part only a widget cares about: remembering the last feed that succeeded, so a failed refresh dims what was there instead of blanking it.
/// One entry per timeline, never a schedule of several. The rows are only true at the moment they are read — a second entry an hour out would assert that the same files were the newest ones then, which nothing here knows.
struct ActivityTimelineProvider: TimelineProvider {
    /// `refreshInterval` is how long WidgetKit is asked to wait before rebuilding the timeline.
    ///
    /// Half an hour is a ceiling rather than a promise: the system spends a widget's refreshes as it sees fit and routinely gives fewer. Asking for less would not buy more of them.
    /// While an account stays signed in this interval is the only thing that refreshes the widget; the apps ask for an immediate reload only when they sign in or out, so the widget stops drawing an account that has gone, or starts drawing one that has arrived, without waiting it out.
    private static let refreshInterval: TimeInterval = 30 * 60

    /// `logger` records what the provider decides about a fetch under the `ActivityTimelineProvider` category.
    private static let logger = Logger(for: ActivityTimelineProvider.self)

    /// `rowLimit` is how many rows the largest layout draws, and so how many are kept.
    private static let rowLimit = 10

    /// `fetchLimit` is how many activities the server is asked for.
    ///
    /// More than `rowLimit`, because the server's file filter admits activity types the widget draws no badge for and `ActivityRow` drops those. Asking for exactly the number of rows wanted would leave the large layout short whenever a download or a favourite change landed in the newest ten.
    private static let fetchLimit = 30

    /// `placeholder(in:)` is the redacted shape WidgetKit draws before anything has been fetched, and whenever it wants the widget's outline without its content.
    func placeholder(in _: Context) -> ActivityEntry {
        ActivityEntry(date: .now, content: .redacted)
    }

    /// `getSnapshot(in:completion:)` is what the widget gallery shows.
    ///
    /// A gallery preview must not wait on a network request or show somebody's real files while they are browsing widgets to add, so it answers immediately: the saved feed when there is one, and the redacted bars when there is not.
    func getSnapshot(in context: Context, completion: @escaping @Sendable (ActivityEntry) -> Void) {
        guard context.isPreview == false, let snapshot = ActivityFeedStore.load() else {
            completion(ActivityEntry(date: .now, content: .redacted))
            return
        }

        completion(ActivityEntry(date: .now, content: Self.content(for: snapshot.rows), fetchedAt: snapshot.fetchedAt))
    }

    /// `getTimeline(in:completion:)` fetches the newest activity and hands WidgetKit one entry plus when to come back.
    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<ActivityEntry>) -> Void) {
        Task {
            let entry = await Self.entry()

            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.refreshInterval))))
        }
    }

    /// `content(for:)` is what a set of rows means, which is not a feed at all when there are none.
    ///
    /// A server that answers with nothing and a snapshot saved from one are the same fact, and both have to reach the card as `empty` rather than as a feed of length zero — a feed of length zero draws a header over blank space, which reads as a widget that has failed rather than as a server with nothing to report. Every path that has rows goes through here so there is one answer to that rather than one per call site.
    private static func content(for rows: [ActivityRow]) -> ActivityEntry.Content {
        rows.isEmpty ? .empty : .feed(rows)
    }

    /// `entry()` turns one fetch into the entry that fetch means.
    ///
    /// The two failures that carry over are the transient ones. An unreachable server and a cancelled refresh have learned nothing about what the feed contains, so whatever was last known stays on screen, dimmed and dated. Everything else has learned something definite — there is no account, or the instance has no activity app — and says so plainly, because a stale feed under one of those would be a lie about why it is old.
    private static func entry() async -> ActivityEntry {
        switch await RecentActivity.fetch(limit: fetchLimit, reason: "widget") {
            case let .fetched(rows, account):
                let visible = Array(rows.prefix(rowLimit))
                let fetchedAt = Date.now

                await refreshAvatars(for: visible)
                ActivityFeedStore.save(rows: visible, fetchedAt: fetchedAt)

                // The account may have signed out while this was fetching, in the app's process rather than this one.
                // Checked after saving rather than before, so the two processes cannot interleave between the check
                // and the write: the app clears the credentials before the saved feed, so either this sees them gone
                // and takes the rows back itself, or it saved them before the app's own clear, which removes them.
                // A Keychain that cannot be read says nothing about that, and leaves the rows in place. The photographs
                // just fetched go too, since the app's sign-out may have emptied the cache before they landed.
                if let accounts = try? Keychain.storedAccounts(), accounts.contains(account) == false {
                    logger.notice("The account these rows belong to signed out while they were being fetched; forgetting them")
                    ActivityFeedStore.clear()
                    ServerAvatars.shared.forget(userIDs: visible.compactMap(\.actorID), serverAddress: account.server)
                    return ActivityEntry(date: .now, content: .notSignedIn)
                }

                return ActivityEntry(
                    date: .now,
                    content: content(for: visible),
                    fetchedAt: fetchedAt
                )

            case .noAccount:
                // A signed-out account's rows must not come back as the stale state of the next one. The app clears
                // the saved feed when it signs out, and the widget clears it too whenever the Keychain says nobody is
                // signed in, which covers anything a timeline fetched for that account managed to save after all.
                ActivityFeedStore.clear()
                return ActivityEntry(date: .now, content: .notSignedIn)

            case .endpointUnavailable:
                return ActivityEntry(date: .now, content: .unavailable)

            case .credentialsRejected:
                // The stored app password was revoked, so the account is no longer usable and the widget asks for the
                // same thing a fresh install does: open the app and connect. Its rows go for the reason they do above.
                ActivityFeedStore.clear()
                return ActivityEntry(date: .now, content: .notSignedIn)

            case .cancelled, .unreachable:
                guard let snapshot = ActivityFeedStore.load() else {
                    return ActivityEntry(date: .now, content: .redacted)
                }

                return ActivityEntry(date: .now, content: content(for: snapshot.rows), fetchedAt: snapshot.fetchedAt, isStale: true)
        }
    }

    /// `refreshAvatars(for:)` fetches the profile photograph of everybody the new rows name, so the next draw has them.
    ///
    /// It runs before the entry is handed over rather than lazily from the views, because a widget's views cannot await anything: whatever is not on disk by the time the entry is returned is a monogram until the next refresh. Only actors are asked for — a row without one is the signed-in user, whose own circle the design never fills.
    /// Failures are silent by construction. `ServerAvatars.refresh(userIDs:on:)` throws nothing, and a photograph that could not be fetched draws as the monogram the design falls back to anyway.
    private static func refreshAvatars(for rows: [ActivityRow]) async {
        let userIDs = Set(rows.compactMap(\.actorID))

        guard userIDs.isEmpty == false else {
            return
        }

        guard let account = Keychain.accounts().first, let server = ServerConnection.authenticated(address: account.server) else {
            return
        }

        await ServerAvatars.shared.refresh(userIDs: userIDs, on: server)
    }
}
