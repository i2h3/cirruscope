import AppKit
import os
import WebKit

/// `WebViewController`'s conformance to `WKUIDelegate` handles the web interface's requests that need native UI.
///
/// It grants camera and microphone capture to the configured Nextcloud server without an extra web-view prompt, presents an open panel so the web interface can upload files, and redirects new-window requests into the existing web view. WKWebView shows no file chooser of its own, so without `runOpenPanelWith` an "Upload" action in Nextcloud does nothing; and it would prompt per-site for camera/microphone on top of the one-time macOS system permission. Because the web view only ever loads the trusted server the user signed in to — `WebViewController+WKNavigationDelegate` hands any other host to the system browser — media capture for that origin is granted automatically; any other origin falls back to the default prompt.
/// Nextcloud opens some actions, including certain downloads, in a new window; WKWebView drops those unless a second web view is returned, so `createWebViewWith` loads them in place instead, routing them back through the navigation delegate that starts downloads and offloads external hosts.
/// Every method here logs its entry and each outcome at debug level so the behaviour of a specific window — identified by the appended `logID` — can be reconstructed from a log capture when tracing misbehaviour.
extension WebViewController: WKUIDelegate {
    func webView(_: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy _: WKFrameInfo, type _: WKMediaCaptureType) async -> WKPermissionDecision {
        logger.debug("Deciding media capture permission for origin \(origin.host) (WebViewController \(self.logID))")

        guard let serverHost = Settings.serverAddress?.host, origin.host.caseInsensitiveCompare(serverHost) == .orderedSame else {
            logger.debug("Origin is not the configured server; returning .prompt (WebViewController \(self.logID))")
            return .prompt
        }

        logger.debug("Origin is the configured server; granting media capture (WebViewController \(self.logID))")
        return .grant
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame _: WKFrameInfo) async -> [URL]? {
        logger.debug("Presenting file open panel (multiple selection: \(parameters.allowsMultipleSelection), directories: \(parameters.allowsDirectories)) (WebViewController \(self.logID))")

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false

        let response: NSApplication.ModalResponse

        if let window = webView.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            logger.debug("No host window; running the open panel modally (WebViewController \(self.logID))")
            response = panel.runModal()
        }

        guard response == .OK else {
            logger.debug("File open panel was cancelled; returning nil (WebViewController \(self.logID))")
            return nil
        }

        logger.debug("File open panel returned \(panel.urls.count) file(s) (WebViewController \(self.logID))")
        return panel.urls
    }

    func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        logger.debug("Handling new-window request for \(navigationAction.request.url?.absoluteString ?? "no URL") (WebViewController \(self.logID))")

        // A new-window request (target="_blank" or window.open) has no target frame. WKWebView would silently drop it
        // unless a new web view is returned, so load it in the existing web view instead: that runs it through
        // WebViewController+WKNavigationDelegate, which turns a download into a DownloadManager transfer and hands any
        // other host to the system browser. Returning nil declines a second web view.
        if navigationAction.targetFrame == nil {
            logger.debug("New-window request has no target frame; loading it in the existing web view (WebViewController \(self.logID))")
            webView.load(navigationAction.request)
        } else {
            logger.debug("New-window request already has a target frame; leaving it to that frame (WebViewController \(self.logID))")
        }

        logger.debug("Returning nil to decline a second web view (WebViewController \(self.logID))")
        return nil
    }
}
