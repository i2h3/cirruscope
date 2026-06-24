import AppKit
import WebKit

/// `WebViewController`'s conformance to `WKUIDelegate` handles the web interface's requests that need native UI.
///
/// It grants camera and microphone capture to the configured Nextcloud server without an extra web-view prompt, and presents an open panel so the web interface can upload files. WKWebView shows no file chooser of its own, so without `runOpenPanelWith` an "Upload" action in Nextcloud does nothing; and it would prompt per-site for camera/microphone on top of the one-time macOS system permission. Because the web view only ever loads the trusted server the user signed in to — `WebViewController+WKNavigationDelegate` hands any other host to the system browser — media capture for that origin is granted automatically; any other origin falls back to the default prompt.
extension WebViewController: WKUIDelegate {

    func webView(_: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame _: WKFrameInfo, type _: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard let serverHost = Settings.serverAddress?.host, origin.host.caseInsensitiveCompare(serverHost) == .orderedSame else {
            decisionHandler(.prompt)
            return
        }

        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame _: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false

        guard let window = webView.window else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
            return
        }

        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}
