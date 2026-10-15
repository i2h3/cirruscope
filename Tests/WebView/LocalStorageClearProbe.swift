// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

///
/// `LocalStorageClearProbe` reports how many items a page's local storage still holds after the page's own script stored one and cleared the storage, in a real `WKWebView` with or without a user script installed ahead of the page.
///
/// Both apps keep a Nextcloud page from clearing its local storage by replacing the storage method in a user script that runs at the start of every document, in the main frame alone.
/// That a script installed that way decides what the page's own later call does is a belief about WebKit, so this loads a document that makes the call and reads the outcome back, the way `SecurityOriginProbe` measures origins.
/// The document is a string loaded with an `https` address as its base, so no server and no network are involved, and the web view's data store is a non-persistent one, so nothing is kept.
/// It reports through an alert because that needs no message handler, which keeps the user script exactly as the apps install it.
///
@MainActor
final class LocalStorageClearProbe: NSObject, WKUIDelegate {
    ///
    /// `address` is the base the document is loaded at, an `https` origin whose local storage WebKit makes available.
    ///
    private static let address = URL(string: "https://cloud.example.com/")!

    ///
    /// `document` stores one item, clears local storage, and raises an alert with the number of items left, or with `unavailable` when the page has no local storage to use.
    ///
    private static let document = """
    <script>
    try {
        localStorage.setItem("probe", "kept");
        localStorage.clear();
        alert(String(localStorage.length));
    } catch (error) {
        alert("unavailable");
    }
    </script>
    """

    ///
    /// `webView` is the web view the document is loaded into.
    ///
    private let webView: WKWebView

    ///
    /// `continuation` is the report waiting for the document's alert, or `nil` once it has been answered.
    ///
    private var continuation: CheckedContinuation<String, Never>?

    ///
    /// `init(installing:)` builds a web view that keeps nothing, runs `userScript` at the start of every document in the main frame alone when one is given, and reports its alerts to this probe.
    ///
    private init(installing userScript: String?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        if let userScript {
            configuration.userContentController.addUserScript(WKUserScript(source: userScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.uiDelegate = self
    }

    ///
    /// `remainingItemCount(installing:)` is how many items local storage holds after the page stored one and cleared it, with `userScript` installed ahead of the page when one is given, or `nil` when the page could not use local storage at all.
    ///
    static func remainingItemCount(installing userScript: String?) async -> Int? {
        let report = await LocalStorageClearProbe(installing: userScript).report()
        return Int(report)
    }

    ///
    /// `report()` loads the document and answers the message of the alert it raises.
    ///
    private func report() async -> String {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(Self.document, baseURL: Self.address)
        }
    }

    func webView(_: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame _: WKFrameInfo) async {
        continuation?.resume(returning: message)
        continuation = nil
    }
}
