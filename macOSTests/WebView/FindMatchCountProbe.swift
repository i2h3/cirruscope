// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import WebKit

/// `FindMatchCountProbe` measures, in a real `WKWebView`, how many matches WebKit's own `find(_:configuration:)` reports for a query in a document, how many the bundled match-count script counts in the same document, and where the page's selection starts after sequential finds, so `FindMatchCountOracleTests` can assert the first two agree and that a longer query does not move the selection's start.
@MainActor
final class FindMatchCountProbe: NSObject, WKNavigationDelegate {
    /// `address` is the base the fixture document is loaded at.
    private static let address = URL(string: "https://cloud.example.com/")!

    /// `maximumMatchCount` caps WebKit's find loop, so a find that never advances cannot hang the probe.
    private static let maximumMatchCount = 100

    /// `webView` is the web view the document is loaded into.
    private let webView: WKWebView

    /// `continuation` is the report waiting for the document to finish loading, or `nil` once it has resumed.
    private var continuation: CheckedContinuation<Void, Error>?

    /// `init()` builds a web view sized like a real window, so WebKit lays the page out as it would for a user, that keeps nothing and reports its finished navigations to this probe.
    override private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// `counts(inDocument:forQuery:)` loads `document` and answers WebKit's own match count for `query` alongside the bundled script's count in the same document, the script count being `nil` when the bundled script is missing.
    static func counts(inDocument document: String, forQuery query: String) async throws -> (webkit: Int, script: Int?) {
        let probe = FindMatchCountProbe()
        try await probe.load(document)
        let webkit = try await probe.webkitMatchCount(of: query)
        let script = try await probe.scriptMatchCount(of: query)
        return (webkit, script)
    }

    /// `selectionStarts(inDocument:afterFinds:)` loads `document`, runs WebKit's find for each query in `queries` in order with the find bar's configuration, and answers the character offset of the page selection's start from the start of the body after each find (-1 when there is no selection), so a test can assert that a longer query does not move the selection's start.
    static func selectionStarts(inDocument document: String, afterFinds queries: [String]) async throws -> [Int] {
        let probe = FindMatchCountProbe()
        try await probe.load(document)

        var starts: [Int] = []
        for query in queries {
            let configuration = WKFindConfiguration()
            configuration.caseSensitive = false
            configuration.wraps = true
            _ = try await probe.webView.find(query, configuration: configuration)
            let result = try await probe.webView.callAsyncJavaScript("const selection = window.getSelection(); if (selection.rangeCount === 0) { return -1; } const start = selection.getRangeAt(0); const prefix = document.createRange(); prefix.setStart(document.body, 0); prefix.setEnd(start.startContainer, start.startOffset); return prefix.toString().length;", in: nil, contentWorld: .page)
            starts.append(result as? Int ?? -1)
        }

        return starts
    }

    /// `load(_:)` loads `document` and returns once its navigation has finished, or throws when the load fails or the WebContent process dies.
    private func load(_ document: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(document, baseURL: Self.address)
        }
    }

    /// `fail(_:)` resumes a waiting load with `error`, so a failed navigation fails the test instead of hanging it.
    private func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    /// `webkitMatchCount(of:)` is how many times WebKit's own find reports a match for `query`, stepping forward without wrapping until it reports none.
    private func webkitMatchCount(of query: String) async throws -> Int {
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = false

        var count = 0
        while count < Self.maximumMatchCount {
            let result = try await webView.find(query, configuration: configuration)

            if result.matchFound == false {
                break
            }

            count += 1
        }

        return count
    }

    /// `scriptMatchCount(of:)` is what the bundled match-count script answers for `query` in the loaded document, or `nil` when the bundled script is missing.
    private func scriptMatchCount(of query: String) async throws -> Int? {
        guard let functionBody = FindBarViewController.matchCountQuery else {
            return nil
        }

        let result = try await webView.callAsyncJavaScript(functionBody, arguments: ["query": query], in: nil, contentWorld: .page)
        return result as? Int
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        fail(NSError(domain: "FindMatchCountProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "The WebContent process terminated during the load"]))
    }
}
