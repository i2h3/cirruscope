import Cocoa

/// `AppDelegate` is the application delegate of Framecloud and owns the lifecycle of every window the app shows.
///
/// On launch it consults `Settings.serverAddress` to decide whether to present `WebViewController` directly or to first show `ServerAddressViewController`, and it keeps freshly instantiated `NSWindowController`s alive until their windows close.
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
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController: NSWindowController? = if Settings.serverAddress != nil {
            storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? NSWindowController
        } else {
            storyboard.instantiateController(withIdentifier: "ServerAddressWindowController") as? NSWindowController
        }

        guard let windowController else {
            return
        }

        present(windowController: windowController)
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
