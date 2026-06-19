import AppKit
import WebKit

/// `WebViewController`'s conformance to `WKNavigationDelegate` confines the embedded `WKWebView` to the configured Nextcloud server and hands off any navigation that targets a different host to the user's default browser via `NSWorkspace`.
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
}
