import Cocoa
import WebKit

/// `WebViewController` backs the storyboard scene that hosts the embedded `WKWebView` Framecloud uses to display Nextcloud.
///
/// `AppDelegate` presents it on launch when `Settings.serverAddress` is non-`nil`, and `ServerAddressViewController` transitions to it after persisting a freshly validated server address.
/// It injects the bundled `Framecloud.css` stylesheet, bridges custom title-bar drag behaviour, and tracks the state of Nextcloud's sidebar so that `WebViewController+NSMenuItemValidation` can drive the "Show/Hide Sidebar" menu item. The drag and sidebar behaviours are driven by the JavaScript resources enumerated in `WebViewScript`, which are loaded from the bundle on demand rather than embedded in this source file.
/// The hosted `WKWebView` is hidden in the storyboard and only revealed by `WebViewController+WKNavigationDelegate` once its initial page load completes so the user is not exposed to the unstyled intermediate paint of the Nextcloud interface.
class WebViewController: NSViewController, WKScriptMessageHandler {

    // MARK: - Outlets

    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// `webView` is the `WKWebView` that loads `Settings.serverAddress` and renders the Nextcloud web interface.
    ///
    /// `viewDidLoad()` configures it, installs the user scripts produced by `injectCustomStyleSheet()`, `installWindowDragBridge()`, and `installSidebarToggleBridge()`, and triggers the initial navigation.
    /// The view is hidden in the storyboard and unhidden by `webView(_:didFinish:)` after the initial navigation has completed.
    @IBOutlet
    var webView: WKWebView!

    // MARK: - Initial Load

    /// `hasRevealedAfterInitialLoad` is `true` once `webView` has been unhidden after its initial navigation has completed.
    ///
    /// `webView(_:didFinish:)` consults this flag so the reveal happens exactly once, on the first finished navigation, and subsequent navigations do not touch the view's visibility.
    var hasRevealedAfterInitialLoad = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.isInspectable = true
        webView.navigationDelegate = self
        injectCustomStyleSheet()
        installWindowDragBridge()
        installSidebarToggleBridge()

        guard let serverAddress = Settings.serverAddress else {
            preconditionFailure("WebViewController was loaded without a server address in Settings.")
        }

        webView.load(URLRequest(url: serverAddress))
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        layoutWindowControls()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        progressIndicator.startAnimation(self)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutWindowControls()
    }

    // MARK: - Window Controls

    private func layoutWindowControls() {
        guard let window = view.window else {
            return
        }

        let toolbarHeight: CGFloat = 50
        let leadingInset: CGFloat = 20
        let spacing: CGFloat = 23

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for (index, type) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview
            else {
                continue
            }

            let buttonHeight = button.bounds.height
            let topInset = (toolbarHeight - buttonHeight) / 2
            let leading = leadingInset + CGFloat(index) * spacing

            let originInWindow = NSPoint(x: leading, y: window.frame.height - topInset - buttonHeight)

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }

    // MARK: - Window Dragging

    /// `windowDragMessageName` is the script-message name used by the `WebViewScript.windowDrag` user script installed in `installWindowDragBridge()` to ask the host window to begin a drag.
    ///
    /// `userContentController(_:didReceive:)` switches on this value to forward the event to `NSWindow.performDrag(with:)`.
    private static let windowDragMessageName = "windowDrag"

    private func installWindowDragBridge() {
        webView.configuration.userContentController.add(self, name: Self.windowDragMessageName)
        installUserScript(.windowDrag, injectionTime: .atDocumentEnd)
    }

    // MARK: - Sidebar

    /// `sidebarToggleStateMessageName` is the script-message name used by the `WebViewScript.sidebarToggleState` user script installed in `installSidebarToggleBridge()` to report whether Nextcloud's sidebar toggle is available and expanded.
    ///
    /// `userContentController(_:didReceive:)` switches on this value to update `sidebarToggleAvailable` and `sidebarToggleExpanded`.
    private static let sidebarToggleStateMessageName = "sidebarToggleState"

    /// `sidebarToggleAvailable` is `true` while the currently loaded Nextcloud page exposes a sidebar toggle that can be activated.
    ///
    /// `WebViewController+NSMenuItemValidation` reads this value to enable or disable the "Show/Hide Sidebar" menu item.
    var sidebarToggleAvailable = false

    /// `sidebarToggleExpanded` is `true` while Nextcloud's sidebar is currently shown.
    ///
    /// `WebViewController+NSMenuItemValidation` reads this value to switch the title of the "Show/Hide Sidebar" menu item between "Hide Sidebar" and "Show Sidebar".
    var sidebarToggleExpanded = false

    private func installSidebarToggleBridge() {
        webView.configuration.userContentController.add(self, name: Self.sidebarToggleStateMessageName)
        installUserScript(.sidebarToggleState, injectionTime: .atDocumentEnd)
    }

    @IBAction
    func toggleSidebar(_: Any?) {
        guard let source = WebViewScript.sidebarToggle.source else {
            return
        }

        webView.evaluateJavaScript(source)
    }

    // MARK: - Web View Styling

    private func injectCustomStyleSheet() {
        guard
            let url = Bundle.main.url(forResource: "Framecloud", withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let source = """
        (function() {
            var style = document.createElement('style');
            style.textContent = `\(escaped)`;
            document.documentElement.appendChild(style);
        })();
        """

        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        webView.configuration.userContentController.addUserScript(script)
    }

    // MARK: - Script Bridge

    /// `installUserScript(_:injectionTime:)` loads `script` from its bundled resource and registers it on the web view's `WKUserContentController` so it runs at `injectionTime` on every page load, doing nothing if the resource cannot be read.
    ///
    /// `installWindowDragBridge()` and `installSidebarToggleBridge()` call this after registering the script-message handlers their scripts post back to.
    private func installUserScript(_ script: WebViewScript, injectionTime: WKUserScriptInjectionTime) {
        guard let source = script.source else {
            return
        }

        let userScript = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
            case Self.windowDragMessageName:
                guard let window = view.window,
                      let event = NSApp.currentEvent
                else {
                    return
                }
                window.performDrag(with: event)

            case Self.sidebarToggleStateMessageName:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                sidebarToggleAvailable = body["available"] as? Bool ?? false
                sidebarToggleExpanded = body["expanded"] as? Bool ?? false

            default:
                break
        }
    }
}
