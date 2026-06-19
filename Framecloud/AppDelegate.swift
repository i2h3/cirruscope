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

    func applicationDidFinishLaunching(_: Notification) {
        guard let serverAddress = Settings.serverAddress else {
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        Task {
            let identifier: String
            do {
                let server = Server(address: serverAddress)
                let capabilities = try await server.capabilities()

                if let theming = try? capabilities.get(Theming.self) {
                    await Settings.persist(theming: theming)
                }

                let minimumMajorVersion = Settings.minimumSupportedServerMajorVersion

                if capabilities.version.major >= minimumMajorVersion {
                    identifier = "WebViewWindowController"
                } else {
                    presentAlert(title: "Unsupported Server", message: "Framecloud requires Nextcloud version \(minimumMajorVersion) or later. The server at “\(serverAddress.absoluteString)” is running version \(capabilities.version.string).")
                    identifier = "ServerAddressWindowController"
                }
            } catch {
                presentAlert(title: "Could Not Reach Server", message: error.localizedDescription)
                identifier = "ServerAddressWindowController"
            }

            presentWindow(withIdentifier: identifier)
        }
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    @IBAction
    func newWindow(_ sender: Any?) {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateInitialController() as? NSWindowController else {
            return
        }

        present(windowController: windowController, sender: sender)
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
