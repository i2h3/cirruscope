// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

/// `RecordingURLSchemeHandler` stands in for a server for a `WKWebView` in a test, answering every request made under its scheme from memory and recording the path of each one.
@MainActor
final class RecordingURLSchemeHandler: NSObject, WKURLSchemeHandler {
    /// `scheme` is the URL scheme this handler is registered for, one WebKit does not handle itself.
    static let scheme = "cirruscope-probe"

    /// `document` is the HTML every request other than a poll is answered with.
    private let document: String

    /// `pollPath` is the path answered as the page's poll rather than with the document, or `nil` when the documents served poll nothing.
    private let pollPath: String?

    /// `requestedPaths` is the path of every request this handler was asked to answer, polls included, in the order they arrived.
    private(set) var requestedPaths: [String] = []

    /// `rejectsPolls` is whether a poll is answered with HTTP 401 rather than HTTP 200.
    var rejectsPolls = false

    /// `init(document:pollPath:)` answers a request for `pollPath` as a poll, where one is given, and every other request with `document`.
    init(document: String, pollPath: String? = nil) {
        self.document = document
        self.pollPath = pollPath
        super.init()
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        requestedPaths.append(url.path)

        var statusCode = 200
        var contentType = "text/html; charset=utf-8"
        var body = Data(document.utf8)

        if url.path == pollPath {
            statusCode = rejectsPolls ? 401 : 200
            contentType = "text/plain; charset=utf-8"
            body = Data()
        }

        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType, "Cache-Control": "no-store"]) else {
            urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
            return
        }

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {
        // Every request is answered in full before `webView(_:start:)` returns, so there is never one left to stop.
    }
}
