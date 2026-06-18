import Cocoa
import WebKit

class ViewController: NSViewController, WKScriptMessageHandler {
    @IBOutlet weak var webView: WKWebView!

    private static let defaultURL = URL(string: "https://cloud.nextcloud.com")!
    private static let windowDragMessageName = "windowDrag"
    private static let sidebarToggleStateMessageName = "sidebarToggleState"

    private var sidebarToggleAvailable = false
    private var sidebarToggleExpanded = false

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.isInspectable = true
        injectCustomStyleSheet()
        installWindowDragBridge()
        installSidebarToggleBridge()
        webView.load(URLRequest(url: Self.defaultURL))
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        layoutWindowControls()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutWindowControls()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    private func layoutWindowControls() {
        guard let window = view.window else { return }

        let toolbarHeight: CGFloat = 50
        let leadingInset: CGFloat = 20
        let spacing: CGFloat = 23

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for (index, type) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview else {
                continue
            }

            let buttonHeight = button.bounds.height
            let topInset = (toolbarHeight - buttonHeight) / 2
            let leading = leadingInset + CGFloat(index) * spacing

            let originInWindow = NSPoint(
                x: leading,
                y: window.frame.height - topInset - buttonHeight
            )

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case Self.windowDragMessageName:
            guard let window = view.window,
                  let event = NSApp.currentEvent else {
                return
            }
            window.performDrag(with: event)

        case Self.sidebarToggleStateMessageName:
            guard let body = message.body as? [String: Any] else { return }
            sidebarToggleAvailable = body["available"] as? Bool ?? false
            sidebarToggleExpanded = body["expanded"] as? Bool ?? false

        default:
            break
        }
    }

    @IBAction func toggleSidebar(_ sender: Any?) {
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

        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

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

        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

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

        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )

        webView.configuration.userContentController.addUserScript(script)
    }
}
extension ViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarToggleExpanded ? "Hide Sidebar" : "Show Sidebar"
            return sidebarToggleAvailable
        }
        return true
    }
}

