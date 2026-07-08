import AppKit
import os
import WebKit

/// `WebViewController`'s conformance to `WKNavigationDelegate` confines the embedded `WKWebView` to the configured Nextcloud server, hands off any navigation that targets a different host to the user's default browser via `NSWorkspace`, turns responses the web view cannot display or that arrive as attachments into downloads, and reveals the storyboard-hidden web view once its initial page load has completed.
///
/// Any navigation that becomes a download is handed to `DownloadManager.shared`, which takes over as the transfer's delegate so it continues even if this web window closes.
/// Every method here logs its entry and each outcome at debug level so the navigation behaviour of a specific window — identified by the appended `logID` — can be reconstructed from a log capture when tracing misbehaviour.
extension WebViewController: WKNavigationDelegate {
    /// These decision methods use the completion-handler form with an explicit `@objc(...)` selector rather than the
    /// `async` form: WKNavigationDelegate is dispatched by selector, and the `@escaping @MainActor` block matches the
    /// SDK's `WK_SWIFT_UI_ACTOR`. Note that returning `.download` — in either the async or the completion-handler form —
    /// does NOT reliably make WebKit follow up with `…didBecomeDownload:` on this OS under Swift 6 (confirmed by tracing:
    /// the policy returns `.download`, the callback never fires, nothing downloads). So instead of returning `.download`,
    /// a download is started explicitly with `WKWebView.startDownload(using:)`, which hands back the `WKDownload` directly.
    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        logger.debug("Deciding policy for navigation action to \(navigationAction.request.url?.absoluteString ?? "no URL") (WebViewController \(logID))")

        // A link that asks to be downloaded (e.g. an anchor with a `download` attribute) is turned into a download
        // before the host check, so it is never misrouted to the system browser.
        if navigationAction.shouldPerformDownload {
            // WebKit does not reliably deliver `navigationAction:didBecomeDownload:` for a main-frame `.download`
            // decision on this OS with Swift 6 (confirmed by tracing: the policy returns `.download` but the callback
            // never fires). So start the transfer explicitly with `startDownload(using:)`, which hands the `WKDownload`
            // straight to its completion handler, and cancel the navigation instead of relying on the callback.
            logger.debug("Navigation action requests a download; starting it explicitly and cancelling the navigation (WebViewController \(logID))")
            webView.startDownload(using: navigationAction.request) { download in
                DownloadManager.shared.handle(download)
            }
            decisionHandler(.cancel)
            return
        }

        guard let url = navigationAction.request.url,
              let host = url.host,
              let serverHost = Settings.serverAddress?.host,
              host.caseInsensitiveCompare(serverHost) != .orderedSame
        else {
            logger.debug("Navigation action stays on the configured server or has no comparable host; returning .allow (WebViewController \(logID))")
            decisionHandler(.allow)
            return
        }

        NSWorkspace.shared.open(url)
        logger.debug("Navigation action targets external host \(host); opened it in the system browser and returning .cancel (WebViewController \(logID))")
        decisionHandler(.cancel)
    }

    @objc(webView:decidePolicyForNavigationResponse:decisionHandler:)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        logger.debug("Deciding policy for navigation response from \(navigationResponse.response.url?.absoluteString ?? "no URL") (WebViewController \(logID))")

        // Download anything the web view cannot render inline, and anything the server marks as an attachment,
        // which is how Nextcloud delivers a file the user asked to download. As with a download-flagged action,
        // `.download` does not reliably start the transfer here, so re-issue the response's URL as an explicit
        // download and cancel the navigation. `startDownload(using:)` does not re-enter this delegate, so a
        // non-renderable response cannot loop back into another download decision.
        if navigationResponse.canShowMIMEType == false {
            logger.debug("Response MIME type \(navigationResponse.response.mimeType ?? "unknown") is not renderable inline; starting a download and cancelling the navigation (WebViewController \(logID))")
            startDownload(from: navigationResponse.response.url, in: webView)
            decisionHandler(.cancel)
            return
        }

        if let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment")
        {
            logger.debug("Response is marked as an attachment; starting a download and cancelling the navigation (WebViewController \(logID))")
            startDownload(from: navigationResponse.response.url, in: webView)
            decisionHandler(.cancel)
            return
        }

        logger.debug("Response is renderable inline; returning .allow (WebViewController \(logID))")
        decisionHandler(.allow)
    }

    /// `startDownload(from:in:)` starts an explicit `WKDownload` for `url` in `webView` and hands it to `DownloadManager`, the workaround for WebKit not delivering `…didBecomeDownload:` after a `.download` decision on this OS under Swift 6.
    ///
    /// `webView(_:decidePolicyFor:decisionHandler:)` (the response variant) calls it for a response it cannot render or that arrives as an attachment, then cancels the navigation; `startDownload(using:)` re-requests the URL in the web view's context, so the server session's cookies still authorize it.
    private func startDownload(from url: URL?, in webView: WKWebView) {
        guard let url else {
            logger.error("Cannot start a download because the response has no URL (WebViewController \(logID))")
            return
        }

        logger.debug("Starting an explicit download for \(url.absoluteString) (WebViewController \(logID))")
        webView.startDownload(using: URLRequest(url: url)) { download in
            DownloadManager.shared.handle(download)
        }
    }

    /// The explicit @objc selectors are load-bearing: WKNavigationDelegate is dispatched by selector, and without
    /// them Swift emits these under `…didBecome:` (stripping "Download" to match the WKDownload parameter), so
    /// WebKit's call to `…didBecomeDownload:` misses and a started download is never handed to the coordinator.
    @objc(webView:navigationAction:didBecomeDownload:)
    func webView(_: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
        logger.debug("Navigation action became a download; handing it to DownloadManager (WebViewController \(logID))")
        DownloadManager.shared.handle(download)
    }

    @objc(webView:navigationResponse:didBecomeDownload:)
    func webView(_: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
        logger.debug("Navigation response became a download; handing it to DownloadManager (WebViewController \(logID))")
        DownloadManager.shared.handle(download)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        logger.debug("Navigation finished (WebViewController \(logID))")

        // Re-save the window's restorable state after every navigation so a relaunch reopens the page now shown,
        // not the one the window started on. `WebWindow.encodeRestorableState(with:)` reads the current URL.
        view.window?.invalidateRestorableState()

        guard !hasRevealedAfterInitialLoad else {
            logger.debug("Web view already revealed; leaving it in place after this navigation (WebViewController \(logID))")
            return
        }

        hasRevealedAfterInitialLoad = true
        logger.debug("Initial navigation finished; revealing web view (WebViewController \(logID))")

        backgroundImageView.isHidden = true
        visualEffectsView.isHidden = true
        webView.isHidden = false

        // Make the web view the first responder so it joins the key window's responder chain, which
        // enables the Back/Forward/Reload menu items (WKWebView's own validated actions) for this window.
        view.window?.makeFirstResponder(webView)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        logger.error("Web navigation failed: \(error.localizedDescription) (WebViewController \(logID))")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        logger.error("Web provisional navigation failed: \(error.localizedDescription) (WebViewController \(logID))")
    }
}
