// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftUI
import WebKit

///
/// Global iOS app state object.
///
@Observable
@MainActor
class Store {
    ///
    /// The configured account, or `nil` while none is.
    ///
    var account: ServerAccount? {
        didSet {
            server = account.flatMap { ServerConnection.authenticated(address: $0.server) }
        }
    }

    ///
    /// Nextcloud server apps.
    ///
    /// Not persisted. Initially populated on launch by a server response. Occassionally refreshed.
    ///
    var apps: [ServerAppTransferObject]

    ///
    /// The notifications the connected server still has queued for the user.
    ///
    /// Not persisted, deliberately: the server is the only record of these, and nothing in the app needs them to outlive its own process. They are kept for as long as the app runs so the account menu can say how many there are and, in time, list them. The background refresh keeps none of this — it has no store at all — and writes the badge from the same fetch before discarding what came back.
    /// There is no read/unread flag on a Nextcloud notification: the server returns exactly the ones still queued, so this array is the unread set.
    ///
    private(set) var unreadNotifications: [NotificationItem] = []

    ///
    /// How many notifications the connected server still has queued for the user.
    ///
    /// Derived rather than stored, so it cannot come to disagree with the array it counts.
    ///
    var unreadNotificationCount: Int {
        unreadNotifications.count
    }

    ///
    /// Whether a refresh of the unread notifications is already in flight, so a second one does not start beside it.
    ///
    /// Returning to the foreground triggers a refresh, and that happens more often than a fetch takes — pulling Notification Center down and letting it go is one round trip of it — so without this the app would run overlapping requests whose answers could land in either order.
    ///
    private var isRefreshingUnreadNotifications = false

    ///
    /// Counts how many times the apps' icons have changed, so a view drawing them redraws when they do.
    ///
    /// The icons live outside this store — they are files on disk, shared with macOS, found by app identifier — so nothing about `apps` changes when one arrives and observation alone would not notice. This is the one observable thing that does change, and reading it in a view is what subscribes that view to the arrival.
    ///
    private(set) var iconGeneration = 0

    ///
    /// Rainmaker server to interact with the Nextcloud server.
    ///
    /// Kept in step with `account` rather than assigned independently, so the two can never disagree about who the app is talking to. It is built through `ServerConnection.authenticated(address:)` so its credentials and user agent are resolved exactly as macOS resolves them.
    ///
    private(set) var server: Server?

    ///
    /// Records account lifecycle under the `Store` category.
    ///
    private let logger = Logger(for: Store.self)

    ///
    /// Build a store around an account that is already known, or around none.
    ///
    /// The app itself uses `restored()` instead; this initializer is what previews and tests use, so they cannot pick up whatever credentials happen to sit in the Keychain of the machine they run on.
    ///
    init(account: ServerAccount? = nil, apps: [ServerAppTransferObject] = [], notifications: [NotificationItem] = []) {
        self.account = account
        self.apps = apps
        self.unreadNotifications = notifications

        server = account.flatMap { ServerConnection.authenticated(address: $0.server) }
    }

    ///
    /// Build a store around the account this device already holds credentials for, if it holds any.
    ///
    /// The account is read back out of the Keychain rather than from a store of its own: `Keychain.store(_:for:)` files every credential under the address it authenticates against, so one item already carries both halves of a `ServerAccount` and there is no second place for them to fall out of step. macOS keeps the address in `AccountStore` instead, because it already has a database there for the appearance settings and app shortcuts iOS does not have yet.
    ///
    static func restored() -> Store {
        Store(account: Keychain.accounts().first)
    }

    ///
    /// Update the list of available Nextcloud server apps, and the icons they are shown with.
    ///
    /// The list is sorted through the shared `sortedByName()`, which is the same order macOS lists these in — alphabetically by localized name, not in the order the server sends them, for the reason recorded in `DECISIONS.md`.
    /// The icons are fetched after the list is published rather than before, so the menu appears at once with placeholders instead of waiting on a round trip per app. `iconGeneration` is bumped when they land, which is what tells the menu to draw itself again — the apps themselves have not changed, and an icon is not something a value-type snapshot of one carries.
    ///
    func updateApps() {
        guard let server else {
            return
        }

        guard let account else {
            return
        }

        Task {
            let navigationItems = try await server.navigation()

            let apps = navigationItems
                .map { ServerAppTransferObject(id: $0.id, order: $0.order, href: $0.href, name: $0.name) }
                .sortedByName()

            await MainActor.run {
                self.apps = apps
            }

            let didFetchIcons = await ServerAppIcons.shared.refresh(navigationItems, serverAddress: account.server, credentials: account.credentials)

            guard didFetchIcons else {
                return
            }

            await MainActor.run {
                self.iconGeneration += 1
            }
        }
    }

    ///
    /// Fetch the notifications the server has queued for the user, publish them, and update the app icon badge.
    ///
    /// The shape is `updateApps()`': everything decidable without the network is decided here and synchronously, and only the network half goes to a `Task`. The fetch is `UnreadNotifications.fetch(reason:)` — the very call the background refresh makes, with no store involved — so the two cannot arrive at different counts, and the badge is written from the same decision whichever path produced it.
    /// Having no account is deliberately not an early exit. A signed-out app still has a badge to clear, and letting the shared fetch report that there is no account is what clears it without a second rule about when clearing is due.
    /// Only a fetch that actually reached the server replaces what is published. A cancelled or failed one leaves the array exactly as it stands, for the same reason it leaves the badge alone: a network blip must not read as "everything was read".
    ///
    func refreshUnreadNotifications() {
        guard isRefreshingUnreadNotifications == false else {
            logger.debug("A refresh of the unread notifications is already in flight")
            return
        }

        isRefreshingUnreadNotifications = true

        Task {
            defer {
                isRefreshingUnreadNotifications = false
            }

            let outcome = await UnreadNotifications.fetch(reason: "foreground")

            switch outcome {
                case let .fetched(items):
                    unreadNotifications = items

                case .noAccount, .endpointUnavailable, .credentialsRejected:
                    unreadNotifications = []

                case .cancelled, .unreachable:
                    break
            }

            await AppIconBadge.apply(outcome.badgeUpdate)
        }
    }

    ///
    /// The server app a page belongs to, or `nil` when it belongs to none of them.
    ///
    /// The rule is the shared one in `ServerAppTransferObject+Resolution.swift`, so this and the Mac's window reuse cannot come to different conclusions about the same address. It answers `nil` with no account configured, there being no server to resolve against.
    /// Expect `nil` for a short while after every launch as well: `apps` is empty until `updateApps()` has heard back from the server, so nothing resolves until it has. A caller wanting to name the current app therefore needs something to say in the meantime.
    ///
    func app(for url: URL) -> ServerAppTransferObject? {
        guard let account else {
            return nil
        }

        return apps.app(for: url, on: account.server)
    }

    ///
    /// Log out the current user from the connected server.
    ///
    /// The app password is revoked on the server first, so the credential this device is about to forget is invalidated rather than left standing in the account's device list. That request is fire-and-forget: revocation is fail-open — an unreachable server must not be able to keep someone signed in locally — which is the same bargain `AppDelegate.logOut()` strikes on macOS. The web view's site data goes with it, so a later account does not inherit a session from this one.
    /// The background refresh is disarmed and the app icon badge cleared before the credentials it counted with are gone, so the home screen does not keep advertising a number from a session that no longer exists. Neither is strictly load-bearing — the next foreground refresh would find no account and clear the badge anyway — but a badge that outlives a sign-out even briefly is the kind of thing a user reports as the app still being logged in.
    ///
    func logout() {
        logger.notice("Logging out; revoking the app password on the server, clearing the web view's site data, disarming the background refresh, clearing the app icon badge, and clearing the stored credentials")

        if let server {
            Task {
                await ServerConnection.revokeAppPassword(using: server)
            }
        } else {
            logger.debug("No server to revoke an app password on")
        }

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        Keychain.clearAll()

        NotificationRefreshTask.cancelRequest()

        Task {
            await AppIconBadge.apply(.clear)
        }

        apps = []
        unreadNotifications = []
        account = nil
    }
}
