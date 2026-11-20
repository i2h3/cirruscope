// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import WebKit

/// `FindMatchCountProbe` measures, in a real `WKWebView`, how many matches WebKit's own `find(_:configuration:)` reports for a query in a document, and how many the bundled match-count script counts in the same document, so `FindMatchCountOracleTests` can assert the two agree.
@MainActor
final class FindMatchCountProbe: NSObject, WKNavigationDelegate {
    /// `address` is the base the fixture document is loaded at.
    private static let address = URL(string: "https://cloud.example.com/")!

    /// `maximumMatchCount` caps WebKit's find loop, so a find that never advances cannot hang the probe.
    private static let maximumMatchCount = 100

    /// `webView` is the web view the document is loaded into.
    private let webView: WKWebView

    /// `continuation` is the report waiting for the document to finish loading, or `nil` once it has resumed.
    private var continuation: CheckedContinuation<Void, Never>?

    /// `init()` builds a web view that keeps nothing and reports its finished navigations to this probe.
    override private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// `counts(inDocument:forQuery:)` loads `document` and answers WebKit's own match count for `query` alongside the bundled script's count in the same document, the script count being `nil` when the bundled script is missing.
    static func counts(inDocument document: String, forQuery query: String) async throws -> (webkit: Int, script: Int?) {
        let probe = FindMatchCountProbe()
        await probe.load(document)
        let webkit = try await probe.webkitMatchCount(of: query)
        let script = try await probe.scriptMatchCount(of: query)
        return (webkit, script)
    }

    /// `load(_:)` loads `document` and returns once its navigation has finished.
    private func load(_ document: String) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(document, baseURL: Self.address)
        }
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
}
