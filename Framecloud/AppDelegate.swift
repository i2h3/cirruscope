import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [NSWindowController] = []
    private var lastCascadePoint: NSPoint = .zero

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController: NSWindowController?

        if Settings.serverAddress != nil {
            windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? NSWindowController
        } else {
            windowController = storyboard.instantiateController(withIdentifier: "ServerAddressWindowController") as? NSWindowController
        }

        guard let windowController else {
            return
        }

        present(windowController: windowController)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @IBAction func newWindow(_ sender: Any?) {
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

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak windowController] _ in
            guard let self, let windowController else { return }
            self.windowControllers.removeAll { $0 === windowController }
        }

        windowControllers.append(windowController)
        windowController.showWindow(sender)
    }
}
