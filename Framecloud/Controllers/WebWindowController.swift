import Cocoa

/// `WebWindowController` is the window controller for the storyboard "Web Window" scene, carrying the URL its `WebViewController` should load.
///
/// `AppDelegate.presentWebViewWindow(targetURL:)` instantiates it and sets `targetURL` (the URL of a specific server app, or `nil` for the server root) before presenting it; the hosted `WebViewController` reads `targetURL` back from its window controller when it first appears.
class WebWindowController: NSWindowController {

    /// `targetURL` is the URL the hosted `WebViewController` should load, or `nil` to load `Settings.serverAddress`.
    ///
    /// `AppDelegate.presentWebViewWindow(targetURL:)` sets it before the window is shown; `WebViewController.startInitialLoadIfNeeded()` reads it when the view first appears.
    var targetURL: URL?

    override func windowDidLoad() {
        super.windowDidLoad()

        // Opt the window into AppKit state restoration; `AppDelegate` recreates it on relaunch and `WebWindow`
        // encodes which page it shows. The per-window identifier is assigned by whoever creates the window.
        window?.isRestorable = true
        window?.restorationClass = AppDelegate.self
    }
}
