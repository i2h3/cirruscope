// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftUI
import WebKit

///
/// The observable state of the iOS app, which owns the connected account and the `Rainmaker.Server` built from it.
///
/// It holds a projection of the app list `AccountStore` has persisted, because SwiftUI observes this object rather than the store, and starts the notification monitor for the account it holds, whose unread count it passes on.
/// It decides which request may open a server app, more than one menu opening one and what may carry the app password not being a rule to hold twice.
/// It runs the app's two sign-outs: `logout()`, which the user asks for and which revokes the app password on the server, and `requireSignIn()`, which the app makes on its own once the server refuses the app password, and which the sign-in screen then explains.
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
    /// How many notifications the connected server still has queued for the user, as the notification monitor last heard.
    ///
    /// Read through rather than copied, so it cannot come to disagree with the monitor; the monitor is observable, so a view reading this is redrawn when the count changes.
    ///
    var unreadNotificationCount: Int {
        NotificationMonitor.shared.unreadCount
    }

    ///
    /// Whether the server is being asked about the app password after the notification monitor was refused it, so a second refusal does not start a second check beside it.
    ///
    private var isConfirmingRefusedAppPassword = false

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
    init(account: ServerAccount? = nil, apps: [ServerAppTransferObject] = []) {
        self.account = account
        self.apps = apps

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
        // one of them cannot be served once somebody signs in somewhere else. The web view's site data goes with it,
        // as it does with every sign-out, since the web view leaves what a page keeps in place when the page clears
        // it. A Keychain that cannot be read says nothing either way and leaves the store alone.
        if stored?.isEmpty == true, AccountStore.shared.serverAddress != nil {
            Logger(for: Store.self).notice("The store names a server but no credential is stored; signing out what is left, the web view's site data included")
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                Logger(for: Store.self).debug("Cleared the web view's site data")
            }
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
    /// Start watching the account's notifications, or stop watching when there is no account.
    ///
    /// `iOSApp` calls it whenever the app comes to the front and `ServerAddressView` once a sign-in succeeds; starting again for the account already watched only fetches once more, so neither has to know whether the monitor is running.
    /// A refusal of the app password goes on to `confirmRefusedAppPassword(askedAbout:)`, which signs out once the server confirms it. That is the foreground's job alone: the background refresh has no way to say why it signed anybody out, so it leaves that to the monitor the next activation starts.
    ///
    func startNotificationMonitor() {
        guard let account else {
            NotificationMonitor.shared.stop()
            return
        }

        NotificationMonitor.shared.start(for: account) { [weak self] refused in
            Task {
                await self?.confirmRefusedAppPassword(askedAbout: refused)
            }
        }
    }

    ///
    /// Fetch the notifications once more, for Nextcloud's notifications panel having just closed, which is a moment notifications may just have been dismissed in.
    ///
    func refreshUnreadNotifications() {
        NotificationMonitor.shared.refreshNow()
    }

    ///
    /// Ask the server whether it still accepts the app password the notification monitor was refused, and sign out if it does not.
    ///
    /// The refusal is the server's own word about one request, and asking once more through the check both web views make before they sign anybody out is what keeps a single odd answer from costing the user their session.
    /// Only `AppPasswordVerdict.rejected` for the account still signed in when the answer arrives signs out, and every other answer leaves the account as it is, a network that failed in between included; the monitor then stays suspended until the next activation starts it again.
    ///
    private func confirmRefusedAppPassword(askedAbout refused: ServerAccount) async {
        guard isConfirmingRefusedAppPassword == false else {
            logger.debug("The server is already being asked about the app password")
            return
        }

        isConfirmingRefusedAppPassword = true

        defer {
            isConfirmingRefusedAppPassword = false
        }

        logger.notice("The notification monitor was refused the app password; asking the server directly before signing out")

        let verdict = await ServerConnection.verifyAppPassword(at: refused.server, as: refused.credentials)

        guard verdict.signsOut(askedAbout: refused, signedIn: account) else {
            logger.notice("Keeping the account: the server's answer was \(String(describing: verdict), privacy: .public), or the account changed while it was being asked")
            return
        }

        requireSignIn()
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
        logger.notice("Logging out; revoking the app password on the server, clearing the web view's site data, disarming the background refresh, stopping the notification monitor, and signing out of the store, which clears the stored credentials and withdraws every notification")

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
    /// The counterpart of `logout()` for the case where the app is signing the user out rather than the user.
    /// `NextcloudNavigationDecider` calls it only once the server has answered HTTP 401 to an authenticated request asking whether it still accepts the stored app password, which is the one answer that rules out an expired browser session and names the credential itself as what is being refused.
    /// A page re-requested with the stored app password landing back on the server's sign-in form is not reason enough, since the stale page's own script produces exactly that while the server still accepts the password.
    /// `confirmRefusedAppPassword(askedAbout:)` calls it too, once the notification monitor has been refused the app password and the same check has confirmed the refusal for the account still signed in.
    /// Unlike `logout()` it does not revoke the app password: the server has just rejected it, so there is nothing left to revoke and the request would only fail. What it adds instead is `wasSignedOutBySystem`, which is what makes the sign-in screen explain why it is there. macOS strikes the same bargain in `AppDelegate.requireSignIn()`.
    ///
    func requireSignIn() {
        logger.notice("The stored app password is no longer accepted; clearing the web view's site data, disarming the background refresh, stopping the notification monitor, and signing out of the store without revoking the app password")

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
    /// The web view's site data goes with the credentials, so a later account does not inherit a session from this one, and so does everything `AccountStore.disconnect()` forgets, the cached avatars of everyone whose activity this account could see included. The background refresh is disarmed before the credentials it counts with are gone, and the notification monitor is stopped, which clears the app icon badge, so the home screen does not keep advertising a number from a session that no longer exists; a badge that outlives a sign-out even briefly is the kind of thing a user reports as the app still being logged in. The notifications already delivered are withdrawn by the store's sign-out, which every sign-out of either app runs.
    ///
    private func discardSession() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        NotificationRefreshTask.cancelRequest()
        NotificationMonitor.shared.stop()

        // The credentials, the persisted account and every cache go through the store's own sign-out, which every one of
        // the Mac's sign-outs runs too, so the list of what a sign-out forgets cannot drift between them. What the
        // store holds about the server — its address, the app list, and every other domain hanging off the same
        // `Account` record — is no secret, but all of it describes a server this device is no longer signed in to,
        // in a file that is not encrypted. Branding outliving a sign-out would only be untidy, but the avatar caches
        // hold photographs of the people on that server, the widget's saved feed names their files, and the
        // delivered notifications name both, and those must not survive the account that was allowed to see them.
        AccountStore.shared.disconnect()

        apps = []
        account = nil
    }
}
