import Cocoa
import Rainmaker

/// `AppDelegate` is the application delegate of Framecloud and owns the lifecycle of every window the app shows.
///
/// On launch it consults `Settings.serverAddress` to decide whether to present `WebViewController` directly or to first show `ServerAddressViewController`. When a server address is already configured it first re-validates the server's capabilities against `Settings.minimumSupportedServerMajorVersion` and falls back to `ServerAddressViewController` if the server is unreachable or runs an unsupported major version. It also keeps freshly instantiated `NSWindowController`s alive until their windows close.
@main
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

    func applicationDidFinishLaunching(_: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        rebuildServerAppsMenu()
        presentInitialWindow()
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
        if !hasVisibleWindows, windowControllers.isEmpty {
            presentInitialWindow()
        }

        return true
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    @IBAction
    func newWindow(_: Any?) {
        presentInitialWindow()
    }

    /// `presentInitialWindow()` validates the configured server and presents the window the app should show for the current state: `WebViewWindowController` when a supported server is reachable, otherwise `ServerAddressWindowController`.
    ///
    /// `applicationDidFinishLaunching(_:)` calls it on launch, `applicationShouldHandleReopen(_:hasVisibleWindows:)` calls it when the user reactivates the app while no windows are open, and `newWindow(_:)` calls it for the "New Window" menu item, so all three entry points share the same launch logic.
    private func presentInitialWindow() {
        guard let serverAddress = Settings.serverAddress else {
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        guard let server = ServerConnection.authenticated(address: serverAddress) else {
            // The address is configured but no credentials are stored, so the user must log in again.
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        Task {
            do {
                switch try await ServerConnection.validate(server) {
                    case .supported:
                        presentWebViewWindow()
                        await ServerConnection.refreshNavigationApps(using: server)

                    case let .unsupported(version):
                        presentAlert(title: "Unsupported Server", message: "Framecloud requires Nextcloud version \(Settings.minimumSupportedServerMajorVersion) or later. The server at “\(serverAddress.absoluteString)” is running version \(version).")
                        presentWindow(withIdentifier: "ServerAddressWindowController")
                }
            } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
                // The stored app password was revoked on the server; discard it and require a new login.
                Keychain.clearAll()
                presentWindow(withIdentifier: "ServerAddressWindowController")
            } catch {
                presentAlert(title: "Could Not Reach Server", message: error.localizedDescription)
                presentWindow(withIdentifier: "ServerAddressWindowController")
            }
        }
    }

    /// `presentWebViewWindow(targetURL:)` opens and tracks a web window, loading `targetURL` when given or `Settings.serverAddress` otherwise.
    ///
    /// `presentInitialWindow()` and `ServerAddressViewController` open the root window through it, and `openServerApp(_:)` opens app-specific windows, so every web window is created, cascaded, and retained the same way.
    func presentWebViewWindow(targetURL: URL? = nil) {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? WebWindowController else {
            return
        }

        windowController.targetURL = targetURL
        present(windowController: windowController)
    }

    /// `openServerApp(_:)` brings the web window already showing `app` to the front, or opens a new window loading the app when none is open.
    ///
    /// The currently shown app of each window is reported by `WebViewController.currentAppID`. It does nothing when no server address is configured.
    func openServerApp(_ app: ServerApp) {
        guard let serverAddress = Settings.serverAddress else {
            return
        }

        if let existing = windowControllers.first(where: { ($0.contentViewController as? WebViewController)?.currentAppID == app.id }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let url = URL(string: app.href, relativeTo: serverAddress)?.absoluteURL else {
            return
        }

        presentWebViewWindow(targetURL: url)
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
        rebuildServerAppsMenu()
    }

    /// `rebuildServerAppsMenu()` replaces the dynamic server-app items in the View menu with the current `Settings.serverApps`, applying each app's configured shortcut.
    ///
    /// It removes the items it previously inserted and inserts the current apps directly after `serverAppsSeparator`, which keeps them within the storyboard's bracketed section.
    private func rebuildServerAppsMenu() {
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
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: identifier) as? NSWindowController else {
            return
        }

        present(windowController: windowController)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func present(windowController: NSWindowController, sender: Any? = nil) {
        guard let window = windowController.window else {
            return
        }

        lastCascadePoint = window.cascadeTopLeft(from: lastCascadePoint)

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak windowController] _ in
            guard let self, let windowController else {
                return
            }
            windowControllers.removeAll { $0 === windowController }
        }

        windowControllers.append(windowController)
        windowController.showWindow(sender)
    }
}
