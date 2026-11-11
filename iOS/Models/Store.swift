// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftUI
import WebKit

/// The observable state of the iOS app, which owns the connected account and the `Rainmaker.Server` built from it.
@Observable
@MainActor
class Store {
    /// The configured account, or `nil` while none is.
    var account: ServerAccount? {
        didSet {
            server = account.flatMap { ServerConnection.authenticated(address: $0.server) }
        }
    }

    /// Nextcloud server apps.
    var apps: [ServerAppTransferObject]

    /// How many notifications the connected server still has queued for the user, as the notification monitor last heard.
    ///
    /// Read through rather than copied, so it cannot come to disagree with the monitor; the monitor is observable, so a view reading this is redrawn when the count changes.
    var unreadNotificationCount: Int {
        NotificationMonitor.shared.unreadCount
    }

    /// Whether the server is being asked about the app password after the notification monitor was refused it, so a second refusal does not start a second check beside it.
    private var isConfirmingRefusedAppPassword = false

    /// Whether the app signed the user out on its own initiative rather than because the user asked it to.
    private(set) var wasSignedOutBySystem = false

    /// Counts how many times the apps' icons have changed, so a view drawing them redraws when they do.
    private(set) var iconGeneration = 0

    /// The photograph the signed-in account uploaded to the server, or `nil` when it has none or none has been downloaded yet.
    private(set) var accountPhoto: CGImage?

    /// Rainmaker server to interact with the Nextcloud server.
    private(set) var server: Server?

    /// Records account lifecycle under the `Store` category.
    private let logger = Logger(for: Store.self)

    /// Keeps `apps` and `iconGeneration` in step with what `AccountStore` has persisted.
    private var serverAppsObserver: (any NSObjectProtocol)?

    /// Keeps `accountPhoto` in step with who `AccountStore` records the account signs in as, and with the photograph `ServerConnection` downloads for it.
    private var currentUserObserver: (any NSObjectProtocol)?

    /// Build a store around an account that is already known, or around none.
    init(account: ServerAccount? = nil, apps: [ServerAppTransferObject] = [], accountPhoto: CGImage? = nil) {
        self.account = account
        self.apps = apps
        self.accountPhoto = accountPhoto

        server = account.flatMap { ServerConnection.authenticated(address: $0.server) }

        serverAppsObserver = NotificationCenter.default.addObserver(forName: .serverAppsDidChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.adoptPersistedApps()
            }
        }

        currentUserObserver = NotificationCenter.default.addObserver(forName: .currentUserDidChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.accountPhoto = AccountStore.shared.userPhoto
            }
        }
    }

    /// Re-read the persisted app list, and note that whatever draws it should draw it again.
    private func adoptPersistedApps() {
        apps = AccountStore.shared.serverApps
        iconGeneration += 1
    }

    /// Build a store around the account this device already holds credentials for, if it holds any.
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

        return Store(account: stored?.first, apps: AccountStore.shared.serverApps, accountPhoto: AccountStore.shared.userPhoto)
    }

    /// Update the list of available Nextcloud server apps, and the icons they are shown with, and who the account signs in as, with its picture.
    func updateApps() {
        guard let server else {
            return
        }

        Task {
            await ServerConnection.refreshNavigationApps(using: server)

            // Straight after the apps, which repair a store that never learned its address, and before the Spotlight
            // domains, because the account's picture is on screen and they are not.
            await ServerConnection.refreshCurrentUser(using: server)

            // After the apps, and awaited rather than run beside them, because both write to the same store on the
            // same actor and there is nothing waiting on the second: what it feeds is Spotlight and the Shortcuts
            // app rather than anything on screen.
            await ServerConnection.refreshConversations(using: server)
            await ServerConnection.refreshNotes(using: server)
            await ServerConnection.refreshCollectives(using: server)
        }
    }

    /// Start watching the account's notifications, or stop watching when there is no account.
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

    /// Fetch the notifications once more, for Nextcloud's notifications panel having just closed, which is a moment notifications may just have been dismissed in.
    func refreshUnreadNotifications() {
        NotificationMonitor.shared.refreshNow()
    }

    /// Ask the server whether it still accepts the app password the notification monitor was refused, and sign out if it does not.
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

    /// The server app a page belongs to, or `nil` when it belongs to none of them.
    func app(for url: URL) -> ServerAppTransferObject? {
        guard let account else {
            return nil
        }

        return apps.app(for: url, on: account.server)
    }

    /// The request that opens `app` on the connected server, signed in as the account, or `nil` when there is no account or the path the server gave for it leaves the server.
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

    /// Log out the current user from the connected server.
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

    /// Sign the user out because the server no longer accepts the stored app password, and say so.
    func requireSignIn() {
        logger.notice("The stored app password is no longer accepted; clearing the web view's site data, disarming the background refresh, stopping the notification monitor, and signing out of the store without revoking the app password")

        wasSignedOutBySystem = true

        discardSession()
    }

    /// Note that the user has read why they were signed out, so it is not said to them twice.
    func acknowledgeSignOut() {
        wasSignedOutBySystem = false
    }

    /// Forget everything this device holds about the connected account, which is the half `logout()` and `requireSignIn()` have in common.
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
        accountPhoto = nil
        account = nil
    }
}
