import Cocoa
import WebKit

/// `WebViewController` backs the storyboard scene that hosts the embedded `WKWebView` Framecloud uses to display Nextcloud.
///
/// `AppDelegate` presents it on launch when `Settings.serverAddress` is non-`nil`, and `ServerAddressViewController` transitions to it after persisting a freshly validated server address.
/// It injects the bundled `Framecloud.css` stylesheet, bridges custom title-bar drag behaviour, and tracks the state of Nextcloud's sidebar so that `WebViewController+NSMenuItemValidation` can drive the "Show/Hide Sidebar" menu item.
class WebViewController: NSViewController, WKScriptMessageHandler {

    /// `webView` is the `WKWebView` that loads `Settings.serverAddress` and renders the Nextcloud web interface.
    ///
    /// `viewDidLoad()` configures it, installs the user scripts produced by `injectCustomStyleSheet()`, `installWindowDragBridge()`, and `installSidebarToggleBridge()`, and triggers the initial navigation.
    @IBOutlet
    var webView: WKWebView!

    /// `windowDragMessageName` is the script-message name used by the user script installed in `installWindowDragBridge()` to ask the host window to begin a drag.
    ///
    /// `userContentController(_:didReceive:)` switches on this value to forward the event to `NSWindow.performDrag(with:)`.
    private static let windowDragMessageName = "windowDrag"

    /// `sidebarToggleStateMessageName` is the script-message name used by the user script installed in `installSidebarToggleBridge()` to report whether Nextcloud's sidebar toggle is available and expanded.
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

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.isInspectable = true
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

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutWindowControls()
    }

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

    @IBAction
    func toggleSidebar(_: Any?) {
        let script = """
        (function() {
            var element = document.querySelector('.app-navigation-toggle');
            if (element) {
                element.click();
            }
        })();
        """

        webView.evaluateJavaScript(script)
    }

    private func installSidebarToggleBridge() {
        let controller = webView.configuration.userContentController
        controller.add(self, name: Self.sidebarToggleStateMessageName)

        let source = """
        (function() {
            function reportState() {
                var element = document.querySelector('.app-navigation-toggle');
                var available = !!element;
                var expanded = available && element.getAttribute('aria-expanded') === 'true';
                window.webkit.messageHandlers.sidebarToggleState.postMessage({
                    available: available,
                    expanded: expanded
                });
            }

            reportState();

            var observer = new MutationObserver(function() {
                reportState();
            });

            observer.observe(document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['aria-expanded', 'class']
            });
        })();
        """

        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        controller.addUserScript(script)
    }

    private func installWindowDragBridge() {
        let controller = webView.configuration.userContentController
        controller.add(self, name: Self.windowDragMessageName)

        let source = """
        (function() {
            var interactiveSelector = 'a, button, input, textarea, select, label, [role="button"], [role="link"], [contenteditable="true"], [contenteditable=""]';

            document.addEventListener('mousedown', function(event) {
                if (event.button !== 0) {
                    return;
                }

                var header = document.querySelector('#header');
                if (!header || !header.contains(event.target)) {
                    return;
                }

                if (event.target.closest(interactiveSelector)) {
                    return;
                }

                window.webkit.messageHandlers.windowDrag.postMessage({});
            }, true);
        })();
        """

        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        controller.addUserScript(script)
    }

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
}
