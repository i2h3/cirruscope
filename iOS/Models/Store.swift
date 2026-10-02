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
    /// A projection of what `AccountStore` has persisted, refreshed whenever the store announces that the list changed. It is held here rather than read through on every access because SwiftUI observes this object, not the store.
    /// The persisted list it projects survives a relaunch, and `restored()` seeds this from it, which is what lets a menu be drawn before the server has answered — or at all, on a launch with no network.
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
    /// Whether the app signed the user out on its own initiative rather than because the user asked it to.
    ///
    /// `ServerAddressView` reads it to explain itself: a sign-in screen the user did not ask for looks like the app forgot them, and the alert is what says otherwise. A user-initiated `logout()` deliberately leaves it alone, there being nothing to explain.
    ///
    private(set) var wasSignedOutBySystem = false

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
    /// Keeps `apps` and `iconGeneration` in step with what `AccountStore` has persisted.
    ///
    /// The store announces a change rather than being polled, and a refresh is announced twice — by the store when the list itself lands and by `ServerConnection` again when the icons do — which is what lets a menu be drawn immediately and then redrawn with artwork. Reading the store from here rather than awaiting the refresh is what preserves that: awaiting it would hold the list back until the icons had been fetched.
    /// The closure is `@Sendable` by the parameter's own type, so it does not inherit this initializer's main-actor isolation and no dynamic isolation check is emitted at its entry point; the hop inside is therefore a real hop rather than the trap described in AGENTS.md → Concurrency. Nothing crosses it but the decision to re-read.
    /// The token is kept for the life of this object and never removed, which is deliberate rather than an omission. A `deinit` is `nonisolated` and so cannot read a main-actor property, and the alternatives — an unsafe opt-out, or making this an `NSObject` for the selector-based registration that does clean itself up — both cost more than the thing they buy: the app builds exactly one `Store` and keeps it for as long as it runs, and the observer holds `self` weakly, so the one belonging to a preview's discarded store fires into nothing.
    ///
    private var serverAppsObserver: (any NSObjectProtocol)?

    ///
    /// Build a store around an account that is already known, or around none.
    ///
    /// The app itself uses `restored()` instead; this initializer is what previews and tests use, so they cannot pick up whatever credentials happen to sit in the Keychain of the machine they run on.
    ///
    init(account: ServerAccount? = nil, apps: [ServerAppTransferObject] = [], notifications: [NotificationItem] = []) {
        self.account = account
        self.apps = apps
        unreadNotifications = notifications

        server = account.flatMap { ServerConnection.authenticated(address: $0.server) }

        serverAppsObserver = NotificationCenter.default.addObserver(forName: .serverAppsDidChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.adoptPersistedApps()
            }
        }
    }

    ///
    /// Re-read the persisted app list, and note that whatever draws it should draw it again.
    ///
    /// `iconGeneration` is bumped on every announcement rather than only on the one that follows an icon fetch. The apps themselves are value snapshots and carry no icon, so a view drawing one has nothing else to observe; bumping on both announcements costs one redraw of the menus listing the apps, neither of which is usually on screen, and is what makes the icons appear when they land.
    ///
    private func adoptPersistedApps() {
        apps = AccountStore.shared.serverApps
        iconGeneration += 1
    }

    ///
    /// Build a store around the account this device already holds credentials for, if it holds any.
    ///
    /// The account is still read back out of the Keychain rather than from `AccountStore`: `Keychain.store(_:for:)` files every credential under the address it authenticates against, so one item already carries both halves of a `ServerAccount`, and reading it from there is what keeps restoring the account from depending on what the store holds. The store is told the same address at sign-in and is the authority on everything derived from it, the app list included — which is why the apps come from there and arrive already populated on a relaunch.
    ///
    static func restored() -> Store {
        let stored = try? Keychain.storedAccounts()

        // The store still names a server while the Keychain says, for certain, that no credential is left: a
        // sign-out that did not finish, or a store carried to a device the credential, being this device's only,
        // did not travel to. Finish it, so Spotlight stops offering that server's things and a request latched for
        // one of them cannot be served once somebody signs in somewhere else. A Keychain that cannot be read says
        // nothing either way and leaves the store alone.
        if stored?.isEmpty == true, AccountStore.shared.serverAddress != nil {
            Logger(for: Store.self).notice("The store names a server but no credential is stored; signing out what is left")
            AccountStore.shared.disconnect()
        }

        return Store(account: stored?.first, apps: AccountStore.shared.serverApps)
    }

    ///
    /// Update the list of available Nextcloud server apps, and the icons they are shown with.
    ///
    /// The fetch, the mapping out of `Rainmaker.NavigationItem`, the persistence and the icon download are all `ServerConnection.refreshNavigationApps(using:)`, shared with macOS. One implementation rather than one per app is deliberate: two copies of the same four steps are exactly the kind of pair that drifts, down to the order the two apps list the same apps in.
    /// Nothing is read back here. The refresh announces itself when the list lands and again when the icons do, and `adoptPersistedApps()` picks both up — so the menu still appears before the icons rather than waiting on a round trip per app.
    ///
    func updateApps() {
        guard let server else {
            return
        }

        Task {
            await ServerConnection.refreshNavigationApps(using: server)

            // After the apps, and awaited rather than run beside them, because both write to the same store on the
            // same actor and there is nothing waiting on the second: what it feeds is Spotlight and the Shortcuts
            // app rather than anything on screen.
            await ServerConnection.refreshConversations(using: server)
            await ServerConnection.refreshNotes(using: server)
            await ServerConnection.refreshCollectives(using: server)
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
    /// Expect `nil` for a short while after a first sign-in as well: `apps` is empty until `updateApps()` has heard back from the server, so nothing resolves until it has. A relaunch starts from the persisted list instead, but a caller wanting to name the current app still needs something to say in the meantime.
    ///
    func app(for url: URL) -> ServerAppTransferObject? {
        guard let account else {
            return nil
        }

        return apps.app(for: url, on: account.server)
    }

    ///
    /// The request that opens `app` on the connected server, signed in as the account, or `nil` when there is no account or the path the server gave for it leaves the server.
    ///
    /// The path comes from the server, and `ServerAccount.authenticatedRequest(for:)` attaches the app password to whatever it is handed, so it is proven to stay on the connected server first. macOS resolves the same value the same way, through the same type.
    /// It lives here rather than on a screen because more than one menu opens an app — a window's own title menu, and the iPad's View menu, which reaches whichever window is in front — and what may carry the app password is not a rule to hold twice.
    ///
    func request(opening app: ServerAppTransferObject) -> URLRequest? {
        guard let account else {
            return nil
        }

        guard let target = SameOriginURL(path: app.href, relativeTo: account.server) else {
            logger.error("The path offered for server app \(app.id, privacy: .public) does not stay on the connected server; refusing to open it")
            return nil
        }

        return account.authenticatedRequest(for: target.url)
    }

    ///
    /// Log out the current user from the connected server.
    ///
    /// The app password is revoked on the server first, so the credential this device is about to forget is invalidated rather than left standing in the account's device list. That request is fire-and-forget: revocation is fail-open — an unreachable server must not be able to keep someone signed in locally — which is the same bargain `AppDelegate.logOut()` strikes on macOS. Everything after it is `discardSession()`, which is also what `requireSignIn()` does; revoking is the whole of the difference between the two.
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

        discardSession()
    }

    ///
    /// Sign the user out because the server no longer accepts the stored app password, and say so.
    ///
    /// The counterpart of `logout()` for the case where the app is signing the user out rather than the user. `NextcloudNavigationDecider` calls it when a page re-requested with the stored app password lands back on the server's sign-in form, which is the point at which an expired browser session has been ruled out and the credential itself is what is being refused.
    /// Unlike `logout()` it does not revoke the app password: the server has just rejected it, so there is nothing left to revoke and the request would only fail. What it adds instead is `wasSignedOutBySystem`, which is what makes the sign-in screen explain why it is there. macOS strikes the same bargain in `AppDelegate.requireSignIn()`.
    ///
    func requireSignIn() {
        logger.notice("The stored app password is no longer accepted; clearing the web view's site data, disarming the background refresh, clearing the app icon badge, and clearing the stored credentials without revoking them")

        wasSignedOutBySystem = true

        discardSession()
    }

    ///
    /// Note that the user has read why they were signed out, so it is not said to them twice.
    ///
    func acknowledgeSignOut() {
        wasSignedOutBySystem = false
    }

    ///
    /// Forget everything this device holds about the connected account, which is the half `logout()` and `requireSignIn()` have in common.
    ///
    /// The web view's site data goes with the credentials, so a later account does not inherit a session from this one, and so does everything `AccountStore.disconnect()` forgets, the cached avatars of everyone whose activity this account could see included. The background refresh is disarmed before the credentials it counts with are gone, and the app icon badge is cleared as the session ends, so the home screen does not keep advertising a number from a session that no longer exists. Neither is strictly load-bearing — the next foreground refresh would find no account and clear the badge anyway — but a badge that outlives a sign-out even briefly is the kind of thing a user reports as the app still being logged in.
    ///
    private func discardSession() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        NotificationRefreshTask.cancelRequest()

        Task {
            await AppIconBadge.apply(.clear)
        }

        // The credentials, the persisted account and every cache go through the store's own sign-out, which every one of
        // the Mac's sign-outs runs too, so the list of what a sign-out forgets cannot drift between them. What the
        // store holds about the server — its address, the app list, and every other domain hanging off the same
        // `Account` record — is no secret, but all of it describes a server this device is no longer signed in to,
        // in a file that is not encrypted. Branding outliving a sign-out would only be untidy, but the avatar caches
        // hold photographs of the people on that server and the widget's saved feed names their files, and those
        // must not survive the account that was allowed to see them.
        AccountStore.shared.disconnect()

        apps = []
        unreadNotifications = []
        account = nil
    }
}
