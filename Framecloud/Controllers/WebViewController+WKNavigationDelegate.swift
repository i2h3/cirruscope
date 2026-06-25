import AppKit
import WebKit

/// `WebViewController`'s conformance to `WKNavigationDelegate` confines the embedded `WKWebView` to the configured Nextcloud server, hands off any navigation that targets a different host to the user's default browser via `NSWorkspace`, and reveals the storyboard-hidden web view once its initial page load has completed.
extension WebViewController: WKNavigationDelegate {

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let host = url.host,
              let serverHost = Settings.serverAddress?.host,
              host.caseInsensitiveCompare(serverHost) != .orderedSame
        else {
            decisionHandler(.allow)
            return
        }

        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        // Re-save the window's restorable state after every navigation so a relaunch reopens the page now shown,
        // not the one the window started on. `WebWindow.encodeRestorableState(with:)` reads the current URL.
        view.window?.invalidateRestorableState()

        guard !hasRevealedAfterInitialLoad else {
            return
        }

        hasRevealedAfterInitialLoad = true
        backgroundImageView.isHidden = true
        visualEffectsView.isHidden = true
        webView.isHidden = false

        // Make the web view the first responder so it joins the key window's responder chain, which
        // enables the Back/Forward/Reload menu items (WKWebView's own validated actions) for this window.
        view.window?.makeFirstResponder(webView)
    }
}
