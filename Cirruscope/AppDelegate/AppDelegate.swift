// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import Rainmaker
import WebKit

/// `AppDelegate` is the application delegate of Cirruscope and owns the lifecycle of every window the app shows.
///
/// On launch it consults `Settings.serverAddress` to decide whether to present `WebViewController` directly or to first show `ServerAddressViewController`. When a server address is already configured it first re-validates the server's capabilities against `Settings.minimumSupportedServerMajorVersion` and falls back to `ServerAddressViewController` if the server is unreachable or runs an unsupported major version. It also keeps freshly instantiated `NSWindowController`s alive until their windows close.
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// `windowControllers` retains every `NSWindowController` that `present(windowController:sender:)` has shown so that their windows are not deallocated while visible.
    ///
    /// Each entry is removed when the corresponding `NSWindow.willCloseNotification` fires.
    private var windowControllers: [NSWindowController] = []

    /// `lastCascadePoint` is the point at which the most recently presented window was cascaded.
    ///
    /// `present(windowController:sender:)` updates it on every call so that subsequent windows opened via the "New Window" menu item are offset from the previous one rather than stacking on top of each other.
    private var lastCascadePoint: NSPoint = .zero

    /// `serverAppsSeparator` is the View-menu separator after which the dynamic server-app menu items are inserted.
    ///
    /// `rebuildServerAppsMenu()` inserts one item per `Settings.serverApps` entry directly after it, so the apps occupy the section the storyboard brackets with a separator above and below.
    @IBOutlet
    var serverAppsSeparator: NSMenuItem!

    /// `serverAppMenuItems` holds the server-app items currently inserted into the View menu so `rebuildServerAppsMenu()` can remove the previous set before inserting an updated one.
    private var serverAppMenuItems: [NSMenuItem] = []

    /// `logger` records launch and window-management activity under the `AppDelegate` category; it is not `private` so `AppDelegate`'s extensions in other files can log through it.
    let logger = Logger(for: AppDelegate.self)

    func applicationDidFinishLaunching(_: Notification) {
        logger.notice("Application finished launching")
        UserNotifier.shared.configure()
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadDidStart), name: .downloadDidStart, object: nil)
        rebuildServerAppsMenu()
        presentInitialWindow(forLaunch: true)
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let apps = Settings.serverApps

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

    func applicationWillTerminate(_: Notification) {
        logger.log("App will terminate")
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    @IBAction
    func newWindow(_: Any?) {
        presentInitialWindow(forLaunch: false)
    }

    /// `openPrivacyPolicy(_:)` opens Cirruscope's online privacy policy in the user's default browser.
    ///
    /// It backs both the Help-menu "Privacy Policy…" item and the "Privacy Policy" button on `ServerAddressViewController`; both target the responder chain rather than this object directly, so a single handler serves every entry point.
    @IBAction
    func openPrivacyPolicy(_: Any?) {
        logger.debug("Opening privacy policy")
        NSWorkspace.shared.open(Settings.privacyPolicy)
    }

    /// `openSupportPage(_:)` opens Cirruscope's online support page in the user's default browser.
    ///
    /// It backs the Help-menu "Get Support…" item, which targets the responder chain.
    @IBAction
    func openSupportPage(_: Any?) {
        logger.debug("Opening support page")
        NSWorkspace.shared.open(Settings.supportURL)
    }

    /// `presentInitialWindow(forLaunch:)` validates the configured server and presents the window the app should show: a `WebViewWindowController` when a supported server is reachable, otherwise a `ServerAddressWindowController`.
    ///
    /// `applicationDidFinishLaunching(_:)` calls it with `forLaunch` set to coordinate with AppKit window restoration: it opens a fresh web window only when none was restored, and if the server is now unreachable, unsupported, or has revoked the credentials it closes any restored web windows so none lingers on a server the app can no longer use. `newWindow(_:)` and `applicationShouldHandleReopen(_:hasVisibleWindows:)` call it with `forLaunch` cleared, which always opens a new web window on success and leaves any already-open windows untouched on failure.
    private func presentInitialWindow(forLaunch: Bool) {
        logger.log("Presenting initial window")

        guard let serverAddress = Settings.serverAddress else {
            logger.info("No server address configured; presenting sign-in")
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        guard let server = ServerConnection.authenticated(address: serverAddress) else {
            // The address is configured but no credentials are stored, so the user must log in again.
            logger.notice("Server configured but no stored credentials; requiring sign-in")
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        Task {
            do {
                switch try await ServerConnection.validate(server) {
                    case .supported:
                        logger.info("Server supported; presenting web window")
                        // At launch the validate round-trip runs after AppKit's local restoration, so any restored
                        // web windows are already tracked; open a fresh one only when nothing was restored. A
                        // user-initiated new window always opens.
                        if forLaunch == false || hasOpenWebWindow == false {
                            presentWebViewWindow()
                        }

                        await ServerConnection.refreshNavigationApps(using: server)

                    case let .unsupported(version):
                        logger.notice("Server at \(serverAddress.absoluteString) runs unsupported version \(version)")
                        if forLaunch {
                            closeWebViewWindows()
                        }

                        presentAlert(title: "Unsupported Server", message: "Cirruscope requires Nextcloud version \(Settings.minimumSupportedServerMajorVersion) or later. The server at “\(serverAddress.absoluteString)” is running version \(version).")
                        presentWindow(withIdentifier: "ServerAddressWindowController")
                }
            } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
                // The stored app password was revoked on the server; discard it and require a new login.
                logger.notice("Stored credentials rejected (401); clearing keychain and requiring sign-in")
                Keychain.clearAll()

                if forLaunch {
                    closeWebViewWindows()
                }

                presentWindow(withIdentifier: "ServerAddressWindowController")
            } catch {
                logger.error("Could not reach server: \(error.localizedDescription)")
                if forLaunch {
                    closeWebViewWindows()
                }

                presentAlert(title: "Could Not Reach Server", message: error.localizedDescription)
                presentWindow(withIdentifier: "ServerAddressWindowController")
            }
        }
    }

    /// `hasOpenWebWindow` is `true` while at least one web window is open, including any AppKit restored at launch.
    ///
    /// `presentInitialWindow(forLaunch:)` reads it at launch to avoid opening a duplicate window when AppKit already restored one.
    private var hasOpenWebWindow: Bool {
        windowControllers.contains { $0 is WebWindowController }
    }

    /// `closeWebViewWindows()` closes every open web window.
    ///
    /// `presentInitialWindow(forLaunch:)` calls it at launch when the server turns out to be unreachable, unsupported, or to have revoked the stored credentials, so a restored window does not linger on a server the app can no longer use.
    private func closeWebViewWindows() {
        logger.debug("Closing web view windows…")

        // Iterate a snapshot: closing a window fires the `willClose` observer that mutates `windowControllers`.
        for windowController in windowControllers.filter({ $0 is WebWindowController }) {
            windowController.close()
        }
    }

    /// `presentWebViewWindow(targetURL:)` opens and tracks a web window, loading `targetURL` when given or `Settings.serverAddress` otherwise.
    ///
    /// `presentInitialWindow()` and `ServerAddressViewController` open the root window through it, and `openServerApp(_:)` opens app-specific windows, so every web window is created, cascaded, and retained the same way.
    func presentWebViewWindow(targetURL: URL? = nil) {
        logger.debug("Presenting web view window…")

        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? WebWindowController else {
            return
        }

        windowController.targetURL = targetURL
        // Give every web window a unique restoration identifier so AppKit tracks and restores each one separately.
        windowController.window?.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        present(windowController: windowController)
    }

    /// `openServerApp(_:)` brings the web window already showing `app` to the front, or opens a new window loading the app when none is open.
    ///
    /// The currently shown app of each window is reported by `WebViewController.currentAppID`. It does nothing when no server address is configured.
    func openServerApp(_ app: ServerApp) {
        logger.log("Opening server app…")

        guard let serverAddress = Settings.serverAddress else {
            return
        }

        if let existing = windowControllers.first(where: { ($0.contentViewController as? WebViewController)?.currentAppID == app.id }) {
            logger.log("Found existing window for server app \(app.id) to bring to front")
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        guard let url = URL(string: app.href, relativeTo: serverAddress)?.absoluteURL else {
            return
        }

        logger.log("Failed to find existing window for server app \(app.id) to bring to front, opening a new web view window")
        presentWebViewWindow(targetURL: url)
    }

    /// `logOut()` performs a full app-level logout: fires off a best-effort revocation of the stored Login Flow v2 app password on the server, closes every window, clears the web view's stored cookies and site data so no session for the old server lingers, clears `Settings.serverAddress` (which cascades into clearing the server's cached theme, version, apps, and the stored Login Flow v2 credentials), and presents a fresh `ServerAddressWindowController`.
    ///
    /// Both `GeneralSettingsViewController.logOut(_:)` (the explicit Settings button) and `WebViewController+WKNavigationDelegate`'s detection of the web view navigating to the server's own logout or login page call this shared implementation, so both entry points behave identically and go through the same tracked window-presentation path as every other window `AppDelegate` creates.
    ///
    /// The credentialed `Server` for revocation is captured synchronously before anything else runs, then handed to an unawaited `Task` so a slow or unreachable server can never delay the window-closing, site-data-clearing, or sign-in-presenting steps below, matching Nextcloud's own fail-open guidance for this call. `Server` captures the app password by value at construction, and `ServerConnection.revokeAppPassword(using:)` never re-reads `Keychain`, so the `Task` remains free to complete the request even after `Settings.serverAddress = nil` clears the same credential from `Keychain` further down in this method.
    func logOut() {
        logger.notice("Logging out; revoking the app password on the server, closing all windows, clearing the web view's site data, and clearing the server address and credentials")

        if let serverAddress = Settings.serverAddress, let server = ServerConnection.authenticated(address: serverAddress) {
            logger.debug("Attempting to revoke the app password on the server before completing local sign-out")
            Task {
                await ServerConnection.revokeAppPassword(using: server)
            }
        } else {
            logger.debug("No server address or stored credentials to revoke an app password for")
        }

        for window in NSApplication.shared.windows {
            window.close()
        }

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        Settings.serverAddress = nil

        presentWindow(withIdentifier: "ServerAddressWindowController")
    }

    /// `showDownloads(_:)` backs the "Downloads" menu item, opening the download history window or bringing it to the front when it is already open.
    ///
    /// It targets the responder chain from the menu item, so this single handler serves the menu; `downloadDidStart()` opens the same window when a transfer begins.
    @IBAction
    func showDownloads(_: Any?) {
        logger.log("Showing downloads…")
        showDownloadsWindow()
    }

    /// `showDownloadsWindow()` brings the single Downloads window to the front, instantiating and tracking it from the storyboard first when none is open, and activates the app so the window comes to the foreground.
    ///
    /// `showDownloads(_:)` and `downloadDidStart()` both call it, so the menu item and a starting download converge on one window rather than each opening its own.
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
    ///
    /// `DownloadManager.handle(_:)` posts `Notification.Name.downloadDidStart` on the main actor, so presenting the window here runs on the main thread.
    @objc
    private func downloadDidStart() {
        logger.log("Download did start")
        showDownloadsWindow()
    }

    @IBAction
    func performServerApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let app = Settings.serverApps.first(where: { $0.id == id })
        else {
            return
        }

        openServerApp(app)
    }

    /// `serverAppsDidChange()` rebuilds the View menu when `Settings` posts that the server apps or their shortcuts changed.
    @objc
    private func serverAppsDidChange() {
        logger.log("Server apps did change")
        rebuildServerAppsMenu()
    }

    /// `rebuildServerAppsMenu()` replaces the dynamic server-app items in the View menu with the current `Settings.serverApps`, applying each app's configured shortcut.
    ///
    /// It removes the items it previously inserted and inserts the current apps directly after `serverAppsSeparator`, which keeps them within the storyboard's bracketed section.
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

        for app in Settings.serverApps {
            let item = menuItem(for: app)
            menu.insertItem(item, at: index)
            serverAppMenuItems.append(item)
            index += 1
        }

        logger.log("Completed server app menu rebuilding")
    }

    /// `menuItem(for:)` builds a menu item that opens `app` via `performServerApp(_:)`, applying the user's configured keyboard shortcut for it when one exists.
    private func menuItem(for app: ServerApp) -> NSMenuItem {
        let item = NSMenuItem(title: app.name, action: #selector(performServerApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.id

        if let shortcut = Settings.appShortcuts[app.id] {
            item.keyEquivalent = shortcut.keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
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
    ///
    /// `present(windowController:sender:)` calls it after cascading and before showing; the restoration path calls it on its own for windows AppKit positions and shows itself, so those are retained without being cascaded or shown a second time.
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
