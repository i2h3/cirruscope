// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import Rainmaker
import StoreKit
import WebKit
import WidgetKit

/// `AppDelegate` is the application delegate of Cirruscope and owns the lifecycle of every window the app shows.
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// `windowControllers` retains every `NSWindowController` that `present(windowController:sender:)` has shown so that their windows are not deallocated while visible.
    private var windowControllers: [NSWindowController] = []

    /// `lastCascadePoint` is the point at which the most recently presented window was cascaded.
    private var lastCascadePoint: NSPoint = .zero

    /// `serverAppsSeparator` is the View-menu separator after which the dynamic server-app menu items are inserted.
    @IBOutlet
    var serverAppsSeparator: NSMenuItem!

    /// `serverAppMenuItems` holds the server-app items currently inserted into the View menu so `rebuildServerAppsMenu()` can remove the previous set before inserting an updated one.
    private var serverAppMenuItems: [NSMenuItem] = []

    /// `logger` records launch and window-management activity under the `AppDelegate` category; it is not `private` so `AppDelegate`'s extensions in other files can log through it.
    let logger = Logger(for: AppDelegate.self)

    func applicationWillFinishLaunching(_: Notification) {
        // Before anything reads a credential: window restoration does, and it runs between this and
        // `applicationDidFinishLaunching(_:)`. The widget extension reads its credentials only from the data-protection Keychain, so a
        // timeline it drew before the move is redrawn now that the credentials are where it looks.
        if Keychain.moveFileBasedItems() > 0 {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        logger.notice("Application finished launching")
        UserNotificationDelegate.shared.configure()
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .keyboardShortcutsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadDidStart), name: .downloadDidStart, object: nil)
        rebuildServerAppsMenu()
        // Tell the App Intents layer how this app opens a server app, before anything can ask it to. An intent run
        // from Spotlight or Siri while Cirruscope was not running launches it and reaches `EntityOpening` on the
        // way, which may be before this line; that request is latched rather than dropped, and installing here is
        // what serves it. A clicked server notification is opened through the same opener, as a page.
        EntityOpening.shared.install { [weak self] request in
            switch request {
                case let .serverApp(app):
                    self?.openServerApp(app)

                case let .page(target):
                    guard self?.isSignedIn == true else {
                        self?.presentSignInWindow()
                        return
                    }

                    // A page rather than an app, so it opens in its own window rather than reusing one: the window
                    // already showing Talk is showing a different conversation, and bringing it forward unchanged
                    // would look like the app had ignored what was asked for.
                    self?.presentWebViewWindow(targetURL: target.url)
            }
        }
        // Keep Spotlight and the Siri/Shortcuts app-parameter options in step with the server's app list.
        ServerAppIndexer.shared.start()
        ConversationIndexer.shared.start()
        NoteIndexer.shared.start()
        CollectiveIndexer.shared.start()
        // Watch the macOS accent color and appearance so open web views keep following the accent color chosen in System Settings.
        AccentColorMonitor.shared.start()
        presentInitialWindow(forLaunch: true)
    }

    func applicationDidBecomeActive(_: Notification) {
        // Keep the Dock badge fresh when the user returns to the app; does nothing while the monitor is stopped.
        NotificationMonitor.shared.refreshNow()

        // Only an open web window is use, and it is what anchors the prompt.
        let viewController = frontmostWebWindow?.contentViewController

        if ReviewRequest.isDueOnActivation(inUse: viewController != nil), let viewController {
            AppStore.requestReview(in: viewController)
        }
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let apps = AccountStore.shared.serverApps

        guard apps.isEmpty == false else {
            return nil
        }

        let menu = NSMenu()

        for app in apps {
            menu.addItem(menuItem(for: app))
        }

        return menu
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        logger.log("App should handle reopen")

        if !hasVisibleWindows, windowControllers.isEmpty {
            presentInitialWindow(forLaunch: false)
        }

        return true
    }

    /// `application(_:continue:restorationHandler:)` opens whatever a user selected from a Spotlight result.
    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        openSpotlightSelection(userActivity)
    }

    func applicationWillTerminate(_: Notification) {
        logger.log("App will terminate")

        // `NSWindow.willCloseNotification` is not posted when the application terminates, so the window delegate's
        // own recording in `WebWindowController+NSWindowDelegate` never runs for a window still open at quit. Record
        // here as well, or a size the user reached by zooming rather than by dragging a resize edge — which fires no
        // live-resize notification either — would be lost on every quit.
        if let window = frontmostWebWindow {
            WebWindowFrame.record(window)
        }
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    /// `newWindow(_:)` opens another web window for the "New Window" menu item and its ⌘N key equivalent.
    @IBAction
    func newWindow(_: Any?) {
        presentInitialWindow(forLaunch: false)
    }

    /// `openPrivacyPolicy(_:)` opens Cirruscope's online privacy policy in the user's default browser.
    @IBAction
    func openPrivacyPolicy(_: Any?) {
        logger.debug("Opening privacy policy")
        NSWorkspace.shared.open(InfoPlist.privacyPolicy)
    }

    /// `openSupportPage(_:)` opens Cirruscope's online support page in the user's default browser.
    ///
    /// It backs the Help-menu "Get Support…" item, which targets the responder chain.
    @IBAction
    func openSupportPage(_: Any?) {
        logger.debug("Opening support page")
        NSWorkspace.shared.open(InfoPlist.support)
    }

    @IBAction
    func writeAppStoreReview(_: Any?) {
        logger.debug("Opening the App Store review page")
        NSWorkspace.shared.open(InfoPlist.appStoreReview)
    }

    /// `presentInitialWindow(forLaunch:)` validates the configured server and presents the window the app should show: a `WebViewWindowController` when a supported server is reachable or merely unreachable — in which case the web view shows its own "Server unreachable" retry UI — and a `ServerAddressWindowController` when no server is configured, no credentials are stored for it, the stored credentials were revoked, or the server runs an unsupported major version.
    /// A configured server with no stored credentials is a sign-out that did not finish, so that case completes it through `AccountStore.disconnect()` before asking for a sign-in — unless the credentials are still in macOS's file-based Keychain, which the move at launch could not carry across, and which asks for a sign-in without signing anything out. A revoked credential goes through `requireSignIn()`, which signs out the same way.
    private func presentInitialWindow(forLaunch: Bool) {
        logger.log("Presenting initial window")

        adoptStoredCredentialsIfTheStoreLostItsAccount()

        guard let serverAddress = AccountStore.shared.serverAddress else {
            logger.info("No server address configured; presenting sign-in")
            presentSignInWindow()
            return
        }

        let storedCredentials: Credentials?

        do {
            storedCredentials = try Keychain.storedCredentials(for: serverAddress)
        } catch {
            // The Keychain refused the read, which says nothing about whether the credential is there: ask for a
            // sign-in, which replaces it, rather than sign out what may be a working account.
            logger.error("The stored credentials could not be read; requiring sign-in without signing out: \(error.localizedDescription, privacy: .public)")
            presentSignInWindow()
            return
        }

        guard let credentials = storedCredentials else {
            // Credentials the move in `applicationWillFinishLaunching(_:)` could not carry across, a TestFlight build
            // whose prompt was denied among them, are still in the file-based Keychain. That is a move to try again on
            // the next launch rather than a sign-out that did not finish, and signing out would delete them.
            guard Keychain.holdsFileBasedItems() == false else {
                logger.error("Server configured but its credentials are still in the file-based Keychain; requiring sign-in without signing out")
                presentSignInWindow()
                return
            }

            // The address is configured but the Keychain holds no credentials for it, so the user must sign in
            // again — and what the store still holds about that server is a sign-out that did not finish, which
            // `1.1.0` left behind whenever the server rejected its app password. Finish it, so the menus and
            // Spotlight stop offering a server nobody is signed in to.
            logger.notice("Server configured but no stored credentials; signing out what is left and requiring sign-in")
            signOutLocally()
            presentSignInWindow()
            return
        }

        guard let server = ServerConnection.authenticated(address: serverAddress) else {
            // Building the server reads the Keychain again, and that read failing where the one above found the
            // credentials is a refusal rather than a sign-out, a locked Keychain or an access check failing for a
            // moment, and a refusal must not delete what it was asked about.
            logger.error("The stored credentials could not be read a second time; requiring sign-in without signing out")
            presentSignInWindow()
            return
        }

        // A user-initiated window must not wait on the network: present it in this run-loop turn and let the
        // validation below run behind it. At launch the window is presented inside the `Task` instead, so it
        // can still be reconciled against whatever AppKit restored.
        if forLaunch == false {
            presentWebViewWindow()
        }

        Task {
            do {
                let outcome = try await ServerConnection.validateAndPersist(server)

                // A sign-out while the validation ran has closed the web windows and presented the sign-in screen
                // already, and everything below would act on an account nobody is signed in to: a fresh web window
                // with nothing to load, an alert about a server nobody is using, a monitor badging the Dock.
                guard ServerConnection.isStillSignedIn(server) else {
                    logger.notice("The account was signed out while the server was being validated; doing nothing with the validation")
                    return
                }

                switch outcome {
                    case let .supported(capabilities):
                        logger.info("Server supported")
                        // At launch the validate round-trip runs after AppKit's local restoration, so any restored
                        // web windows are already tracked; open a fresh one only when nothing was restored. A
                        // user-initiated window was already presented above.
                        if forLaunch, hasOpenWebWindow == false {
                            presentWebViewWindow()
                        }

                        await ServerConnection.refreshNavigationApps(using: server)
                        await ServerConnection.refreshCurrentUser(using: server)
                        // After the apps and after the first window is already on screen, because this is the
                        // slower of the two and nothing waits on it: what it feeds is Spotlight and the Shortcuts
                        // app, neither of which is looking yet.
                        await ServerConnection.refreshConversations(using: server)
                        await ServerConnection.refreshNotes(using: server)
                        await ServerConnection.refreshCollectives(using: server)

                        // Asked again, because the refreshes take far longer than the validation did: a sign-out while
                        // they ran has stopped the monitor already, and starting it now would badge the Dock for an
                        // account nobody is signed in to.
                        guard ServerConnection.isStillSignedIn(server) else {
                            logger.notice("The account was signed out while the refreshes after validation ran; not starting the notification monitor")
                            return
                        }

                        // The notifications endpoint exists only while the server's notifications app is enabled,
                        // which an authenticated validation can tell in advance, sparing a request that would 404.
                        guard capabilities.contains(Notifications.self) else {
                            logger.notice("Notifications capability absent; not starting the notification monitor")
                            NotificationMonitor.shared.stop()
                            return
                        }

                        startNotificationMonitor(for: ServerAccount(server: serverAddress, credentials: credentials))

                    case let .unsupported(capabilities):
                        let version = capabilities.version.string
                        logger.notice("Server at \(serverAddress.absoluteString) runs unsupported version \(version)")
                        NotificationMonitor.shared.stop()
                        // Unconditionally, not only at launch: a window this call presented moments ago must not
                        // linger on a server the app cannot use either, matching what `requireSignIn()` does for
                        // revoked credentials.
                        closeWebViewWindows()

                        presentAlert(title: String(localized: "Unsupported Server", comment: "Alert title shown at launch when the configured server runs a Nextcloud version older than the app supports."), message: String(localized: "Cirruscope requires Nextcloud version \(InfoPlist.minimumSupportedServerMajorVersion) or later. The server at “\(serverAddress.absoluteString)” is running version \(version).", comment: "Alert message shown at launch when the configured server's Nextcloud version is too old; placeholders are the minimum supported major version, the server address, and the server's version."))
                        presentSignInWindow()
                }
            } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
                // A sign-out while the validation ran revokes the very app password this was refused for, and telling
                // the user their credentials are no longer valid after they signed out themselves would be wrong.
                guard ServerConnection.isStillSignedIn(server) else {
                    logger.notice("The server refused credentials that a sign-out has discarded since; not asking for a new sign-in")
                    return
                }

                // The stored app password was revoked on the server; sign out and require a new sign-in.
                requireSignIn()
            } catch {
                guard ServerConnection.isStillSignedIn(server) else {
                    logger.notice("The account was signed out while the server was being validated; not opening a window for it")
                    return
                }

                // The server is unreachable — network down, server offline, DNS/TLS/timeout — as opposed to
                // reporting revoked credentials, which is handled above. This is transient and must not look
                // like a reset: keep the configured server address and stored credentials, keep or open the
                // web window, and let `WebViewController` surface its own "Server unreachable" retry UI.
                // Showing an alert or falling back to the sign-in window here would appear to wipe the user's
                // settings. As in the `.supported` case, only open a fresh window when none was restored; a
                // user-initiated one is already on screen, showing its retry UI without ever having waited for
                // this request to time out.
                logger.error("Could not reach server; leaving the web window to show its retry UI: \(error.localizedDescription)")
                NotificationMonitor.shared.stop()

                if forLaunch, hasOpenWebWindow == false {
                    presentWebViewWindow()
                }
            }
        }
    }

    /// `requireSignIn()` signs out because the server rejected the stored credentials, alerts the user, and returns the app to the sign-in screen.
    func requireSignIn() {
        logger.notice("Credentials rejected; signing out and requiring sign-in")
        signOutLocally()

        presentAlert(
            title: String(localized: "Signed Out", comment: "Alert title shown when the app signs the user out on its own because the server rejected the stored credentials."),
            message: String(localized: "Your Nextcloud credentials are no longer valid, so Cirruscope signed you out. Sign in again to continue.", comment: "Alert message shown when the app signs the user out because the server rejected the stored credentials.")
        )

        presentSignInWindow()
    }

    /// `signOutLocally()` is the part every sign-out shares: it stops the notification monitor, closes every web window, clears the web view's site data and signs out through `AccountStore.disconnect()`, which also withdraws every notification the app delivered.
    private func signOutLocally() {
        NotificationMonitor.shared.stop()
        closeWebViewWindows()

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        AccountStore.shared.disconnect()
    }

    /// `adoptStoredCredentialsIfTheStoreLostItsAccount()` records the server the Keychain holds credentials for as the connected one when the store names no server at all, which is what a store rebuilt empty leaves behind.
    private func adoptStoredCredentialsIfTheStoreLostItsAccount() {
        guard AccountStore.shared.serverAddress == nil else {
            return
        }

        guard let stored = try? Keychain.storedAccounts(), stored.isEmpty == false else {
            return
        }

        guard stored.count == 1, let account = stored.first else {
            logger.error("The store names no server but the Keychain holds credentials for \(stored.count, privacy: .public); signing out rather than choosing one")
            signOutLocally()
            return
        }

        logger.notice("The store names no server but the Keychain holds credentials for one; adopting it rather than signing out")
        AccountStore.shared.connect(to: account.server)
    }

    /// `startNotificationMonitor(for:)` starts watching `account`'s notifications, signing out with an explanation should the server refuse its app password.
    func startNotificationMonitor(for account: ServerAccount) {
        NotificationMonitor.shared.start(for: account) { [weak self] refused in
            guard ServerConnection.isStillSignedIn(at: refused.server, as: refused.credentials) else {
                self?.logger.notice("The notification monitor was refused an app password that is no longer the one signed in; not asking for a new sign-in")
                return
            }

            self?.logger.notice("The notification monitor was refused the app password; requiring sign-in")
            self?.requireSignIn()
        }
    }

    /// `hasOpenWebWindow` is `true` while at least one web window is open, including any AppKit restored at launch.
    var hasOpenWebWindow: Bool {
        windowControllers.contains { $0 is WebWindowController }
    }

    /// `frontmostWebWindow` is the web window the user was last working in — the app's main window when that is one, and otherwise any open web window — or `nil` while none is open.
    private var frontmostWebWindow: NSWindow? {
        if let mainWindow = NSApp.mainWindow, mainWindow is WebWindow {
            return mainWindow
        }

        return windowControllers.first { $0 is WebWindowController }?.window
    }

    /// `closeWebViewWindows()` closes every open web window.
    private func closeWebViewWindows() {
        logger.debug("Closing web view windows…")

        // Iterate a snapshot: closing a window fires the `willClose` observer that mutates `windowControllers`.
        for windowController in windowControllers.filter({ $0 is WebWindowController }) {
            windowController.close()
        }
    }

    /// `presentWebViewWindow(targetURL:)` opens and tracks a web window, loading `targetURL` when given or `AccountStore.serverAddress` otherwise.
    func presentWebViewWindow(targetURL: URL? = nil) {
        logger.debug("Presenting web view window…")

        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? WebWindowController else {
            return
        }

        windowController.targetURL = targetURL
        // Give every web window a unique restoration identifier so AppKit tracks and restores each one separately.
        windowController.window?.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)

        if let window = windowController.window {
            WebWindowFrame.applySize(to: window)
        }

        present(windowController: windowController)
        // Counted here as well, so a day spent in a window opened after the launch activation counts even if the user never leaves the app.
        ReviewRequest.recordDayOfUse()
    }

    /// `openServerApp(_:)` brings the web window already showing `app` to the front, or opens a new window loading the app when none is open.
    func openServerApp(_ app: ServerAppTransferObject) {
        logger.log("Opening server app…")

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        guard isSignedIn else {
            logger.notice("Asked to open server app \(app.id) while no credentials are stored; bringing the sign-in window forward instead")
            presentSignInWindow()
            return
        }

        if let existing = windowControllers.first(where: { ($0.contentViewController as? WebViewController)?.currentApp?.id == app.id }) {
            logger.log("Found existing window for server app \(app.id) to bring to front")
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        // The server chooses this path, and `WebViewController.authenticatedRequest(for:)` will attach the app
        // password to whatever it resolves to, so it has to be proven to stay on the server before it is loaded.
        guard let target = SameOriginURL(path: app.href, relativeTo: serverAddress) else {
            logger.error("The path offered for server app \(app.id) does not stay on the connected server; refusing to open it")
            return
        }

        logger.log("Failed to find existing window for server app \(app.id) to bring to front, opening a new web view window")
        presentWebViewWindow(targetURL: target.url)
    }

    /// `logOut()` performs a full app-level logout: fires off a best-effort revocation of the stored Login Flow v2 app password on the server, closes every window, clears the web view's stored cookies and site data so no session for the old server lingers, disconnects the account via `AccountStore.disconnect()` (which deletes the account — its cached theme and version, and through it the apps, conversations, notes and collectives — and forgets every cache and credential describing the old server, while the keyboard shortcuts and appearance settings, which belong to the device, stay), and presents a fresh `ServerAddressWindowController`.
    func logOut() {
        logger.notice("Logging out; revoking the app password on the server, closing all windows, clearing the web view's site data, and clearing the server address and credentials")

        if let serverAddress = AccountStore.shared.serverAddress, let server = ServerConnection.authenticated(address: serverAddress) {
            logger.debug("Attempting to revoke the app password on the server before completing local sign-out")
            Task {
                await ServerConnection.revokeAppPassword(using: server)
            }
        } else {
            logger.debug("No server address or stored credentials to revoke an app password for")
        }

        // Every window rather than only the web windows, the Settings window included, because what it shows
        // describes the account being signed out of.
        for window in NSApplication.shared.windows {
            window.close()
        }

        signOutLocally()
        presentSignInWindow()
    }

    /// `showDownloads(_:)` backs the "Downloads" menu item, opening the download history window or bringing it to the front when it is already open.
    @IBAction
    func showDownloads(_: Any?) {
        logger.log("Showing downloads…")
        showDownloadsWindow()
    }

    /// `showDownloadsWindow()` brings the single Downloads window to the front, instantiating and tracking it from the storyboard first when none is open, and activates the app so the window comes to the foreground.
    func showDownloadsWindow() {
        if let existing = windowControllers.first(where: { $0.contentViewController is DownloadViewController }) {
            logger.log("Showing existing downloads window…")
            existing.showWindow(self)
        } else {
            logger.log("Showing new downloads window…")
            presentWindow(withIdentifier: "DownloadsWindowController")
        }

        NSApp.activate()
    }

    /// `downloadDidStart()` opens the Downloads window when `DownloadManager` reports that a transfer has begun.
    @objc
    private func downloadDidStart() {
        logger.log("Download did start")
        showDownloadsWindow()
    }

    @IBAction
    func performServerApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let app = AccountStore.shared.serverApps.first(where: { $0.id == id })
        else {
            return
        }

        openServerApp(app)
    }

    /// `serverAppsDidChange()` rebuilds the View menu when `AccountStore` posts that the server apps or the keyboard shortcuts changed, or `ServerConnection` that the apps' icons have landed.
    @objc
    private func serverAppsDidChange() {
        logger.log("Server apps did change")
        rebuildServerAppsMenu()
    }

    /// `rebuildServerAppsMenu()` replaces the dynamic server-app items in the View menu with the current `AccountStore.serverApps`, applying the keyboard shortcut that reaches each app, if any.
    private func rebuildServerAppsMenu() {
        logger.log("Rebuilding server apps menu…")

        guard let menu = serverAppsSeparator?.menu else {
            return
        }

        for item in serverAppMenuItems {
            menu.removeItem(item)
        }

        serverAppMenuItems.removeAll()

        var index = menu.index(of: serverAppsSeparator) + 1

        for app in AccountStore.shared.serverApps {
            let item = menuItem(for: app)
            menu.insertItem(item, at: index)
            serverAppMenuItems.append(item)
            index += 1
        }

        logger.log("Completed server app menu rebuilding")
    }

    /// `menuItem(for:)` builds a menu item that opens `app` via `performServerApp(_:)`, carrying the app's own icon and the keyboard shortcut that reaches it, when `AccountStore.shortcut(forAppID:)` answers one — a shortcut it suppresses as reserved or as another app's is left off.
    private func menuItem(for app: ServerAppTransferObject) -> NSMenuItem {
        let item = NSMenuItem(title: app.name, action: #selector(performServerApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.id
        item.image = Self.icon(for: app)

        // The check is the compiler's, not a second behaviour: the property is new in macOS 27, and the app still
        // deploys to macOS 26, which draws menu images without being asked.
        if #available(macOS 27.0, *) {
            item.preferredImageVisibility = .visible
        }

        if let shortcut = AccountStore.shared.shortcut(forAppID: app.id) {
            item.keyEquivalent = shortcut.keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
    }

    /// `icon(for:)` is the image a server app is listed with: its own, when one has been downloaded, and a generic placeholder when it has not.
    ///
    /// Not private, because the Keyboard Shortcuts settings tab lists the same apps and has to reach the same answer; a second copy of this decision is how two lists of the same thing start looking different.
    static func icon(for app: ServerAppTransferObject) -> NSImage? {
        guard let serverAddress = AccountStore.shared.serverAddress else {
            return NSImage(systemSymbolName: "app.grid", accessibilityDescription: nil)
        }

        return NSImage.serverAppIcon(forAppID: app.id, serverAddress: serverAddress) ?? NSImage(systemSymbolName: "app.grid", accessibilityDescription: nil)
    }

    /// `isSignedIn` is `true` while credentials are stored for the configured server, which is what loading anything from it needs.
    private var isSignedIn: Bool {
        guard let serverAddress = AccountStore.shared.serverAddress else {
            return false
        }

        return Keychain.credentials(for: serverAddress) != nil
    }

    /// `presentSignInWindow()` brings the sign-in window to the front, presenting one only when none is open.
    private func presentSignInWindow() {
        if let existing = windowControllers.first(where: { $0.contentViewController is ServerAddressViewController }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        presentWindow(withIdentifier: "ServerAddressWindowController")
    }

    private func presentWindow(withIdentifier identifier: String) {
        logger.log("Presenting window with identifier \(identifier)…")
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: identifier) as? NSWindowController else {
            return
        }

        present(windowController: windowController)
    }

    private func presentAlert(title: String, message: String) {
        logger.log("Presenting alert with title \(title) and informative text \(message)…")

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func present(windowController: NSWindowController, sender: Any? = nil) {
        logger.log("Presenting window controller \(windowController)…")

        guard let window = windowController.window else {
            return
        }

        lastCascadePoint = window.cascadeTopLeft(from: lastCascadePoint)
        track(windowController)
        windowController.showWindow(sender)
    }

    /// `track(_:)` retains `windowController` so its window survives while visible and drops it once the window closes.
    func track(_ windowController: NSWindowController) {
        logger.log("Tracking window controller \(windowController)…")
        guard let window = windowController.window else {
            return
        }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak windowController] _ in
            // The observer is delivered on the main queue, so the main-actor state it drops the window controller from is safe to touch here.
            MainActor.assumeIsolated {
                guard let self, let windowController else {
                    return
                }
                self.windowControllers.removeAll { $0 === windowController }
            }
        }

        windowControllers.append(windowController)
    }
}
