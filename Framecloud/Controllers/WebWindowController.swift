import Cocoa

/// `WebWindowController` is the window controller for the storyboard "Web Window" scene, carrying the URL its `WebViewController` should load.
///
/// `AppDelegate.presentWebViewWindow(targetURL:)` instantiates it and sets `targetURL` (the URL of a specific server app, or `nil` for the server root) before presenting it; the hosted `WebViewController` reads `targetURL` back from its window controller when it first appears.
class WebWindowController: NSWindowController {

    /// `targetURL` is the URL the hosted `WebViewController` should load, or `nil` to load `Settings.serverAddress`.
    ///
    /// `AppDelegate.presentWebViewWindow(targetURL:)` sets it before the window is shown; `WebViewController.startInitialLoadIfNeeded()` reads it when the view first appears.
    var targetURL: URL?
}
