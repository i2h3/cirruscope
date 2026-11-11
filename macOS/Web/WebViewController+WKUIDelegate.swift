// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `WebViewController`'s conformance to `WKUIDelegate` handles the web interface's requests that need native UI.
extension WebViewController: WKUIDelegate {
    func webView(_: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type _: WKMediaCaptureType) async -> WKPermissionDecision {
        let frameOrigin = frame.securityOrigin
        logger.debug("Deciding media capture permission for page origin \(origin.protocol)://\(origin.host):\(origin.port) and frame origin \(frameOrigin.protocol)://\(frameOrigin.host):\(frameOrigin.port) (WebViewController \(self.logID))")

        let decision = MediaCaptureDecision.forRequest(page: (origin.protocol, origin.host, origin.port), frame: (frameOrigin.protocol, frameOrigin.host, frameOrigin.port), connectedTo: AccountStore.shared.serverAddress)

        switch decision {
            case .grant:
                logger.debug("Page and frame are both on the configured server's origin; granting media capture (WebViewController \(self.logID))")
                return .grant

            case .prompt:
                logger.debug("Page or frame is not on the configured server's origin, or no server is configured; returning .prompt (WebViewController \(self.logID))")
                return .prompt
        }
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

    func webView(_: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        logger.debug("Handling new-window request for \(navigationAction.request.url?.absoluteString ?? "no URL") (WebViewController \(self.logID))")

        guard navigationAction.targetFrame == nil else {
            logger.debug("New-window request already has a target frame; leaving it to that frame (WebViewController \(self.logID))")
            return nil
        }

        guard let url = navigationAction.request.url else {
            logger.debug("New-window request has no URL; ignoring (WebViewController \(self.logID))")
            return nil
        }

        guard let serverAddress = AccountStore.shared.serverAddress else {
            logger.debug("No server is configured, so there is nothing to open this against; ignoring (WebViewController \(self.logID))")
            return nil
        }

        // A link to the sign-out route that asks for a new window is decided here rather than in the window it would
        // open, because only this action says how the navigation began: the new window's own load is the app's, and
        // would read as anything but the user's link. No window is opened for it either way. The context menu's "Open
        // Link in New Window" arrives as `.other` like a script's `window.open()`, and is ignored with it on purpose.
        if NextcloudSessionRoute.matching(url, on: serverAddress) == .signOut {
            guard SignOutRequest.of(navigationAction.navigationType) == .explicit else {
                logger.notice("New-window request targets the configured server's own sign-out link but was not started by activating a link (type \(navigationAction.navigationType.rawValue, privacy: .public)); ignoring it and keeping the account (WebViewController \(self.logID))")
                return nil
            }

            logger.notice("New-window request targets the configured server's own sign-out link; logging out at the app level instead of opening a window (WebViewController \(self.logID))")
            (NSApp.delegate as? AppDelegate)?.logOut()

            return nil
        }

        // The same decision the navigation delegate makes, through the same type: a window opened here loads its
        // target with the app password attached, so "is this the configured server" has to be answered the same way
        // in both places. It used to be answered here by comparing hosts, which let a differently-ported service on
        // the server's own machine be opened in a credentialed window.
        guard WebViewDestination.of(url, connectedTo: serverAddress) == .webView else {
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                logger.debug("New-window request targets \(url.absoluteString), which is off the configured server, but nothing is registered to open it; ignoring (WebViewController \(self.logID))")
                return nil
            }

            logger.debug("New-window request targets \(url.absoluteString), which is off the configured server; handing it to the system (WebViewController \(self.logID))")
            NSWorkspace.shared.open(url)

            return nil
        }

        logger.debug("New-window request stays on the configured server; presenting a new web view window (WebViewController \(self.logID))")
        (NSApp.delegate as? AppDelegate)?.presentWebViewWindow(targetURL: url)

        return nil
    }
}
