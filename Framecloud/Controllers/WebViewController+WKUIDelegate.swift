import WebKit

/// `WebViewController`'s conformance to `WKUIDelegate` grants camera and microphone capture to the configured Nextcloud server without an extra web-view permission prompt.
///
/// WKWebView otherwise shows its own per-site capture request on top of the one-time macOS system permission, so joining a Nextcloud Talk call would prompt twice per device. Because the web view only ever loads the trusted server the user signed in to — `WebViewController+WKNavigationDelegate` hands any other host to the system browser — capture for that origin is granted automatically; any other origin falls back to the default prompt. The one-time macOS system prompts (asked once per device and remembered in System Settings) are unaffected, as they are required by the OS.
extension WebViewController: WKUIDelegate {

    func webView(_: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame _: WKFrameInfo, type _: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let serverHost = Settings.serverAddress?.host, origin.host.caseInsensitiveCompare(serverHost) == .orderedSame else {
            decisionHandler(.prompt)
            return
        }

        decisionHandler(.grant)
    }
}
