// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

/// `SecurityOriginProbe` reports the security origin a real `WKWebView` gives a document, in the scheme, host and port WebKit spells it with.
@MainActor
final class SecurityOriginProbe: NSObject, WKUIDelegate {
    /// `webView` is the web view the document is loaded into.
    private let webView: WKWebView

    /// `continuation` is the report waiting for the document's alert, or `nil` once it has been answered.
    private var continuation: CheckedContinuation<(scheme: String, host: String, port: Int), Never>?

    /// `init()` builds a web view that keeps nothing and reports its alerts to this probe.
    override private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.uiDelegate = self
    }

    /// `reportedOrigin(ofDocumentAt:)` is the origin WebKit gives a document loaded at `address`.
    static func reportedOrigin(ofDocumentAt address: URL) async -> (scheme: String, host: String, port: Int) {
        await SecurityOriginProbe().report(html: "<script>alert('')</script>", baseURL: address)
    }

    /// `reportedOriginOfSandboxedFrame(inDocumentAt:)` is the origin WebKit gives a sandboxed frame inside a document loaded at `address`.
    static func reportedOriginOfSandboxedFrame(inDocumentAt address: URL) async -> (scheme: String, host: String, port: Int) {
        await SecurityOriginProbe().report(html: #"<iframe sandbox="allow-scripts allow-modals" srcdoc="<script>alert('')</script>"></iframe>"#, baseURL: address)
    }

    /// `report(html:baseURL:)` loads `html` at `baseURL` and answers the origin of the first frame to raise an alert.
    private func report(html: String, baseURL: URL) async -> (scheme: String, host: String, port: Int) {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_: WKWebView, runJavaScriptAlertPanelWithMessage _: String, initiatedByFrame frame: WKFrameInfo) async {
        let origin = frame.securityOrigin
        continuation?.resume(returning: (origin.protocol, origin.host, origin.port))
        continuation = nil
    }
}
