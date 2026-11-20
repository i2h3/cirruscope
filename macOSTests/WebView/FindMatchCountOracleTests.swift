// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Testing

/// `FindMatchCountOracleTests` asserts that the bundled match-count script agrees with WebKit's own `find(_:configuration:)` on a fixture page holding visible, hidden, form and script text, both measured in a real `WKWebView` through `FindMatchCountProbe` (issue #98).
@MainActor
struct FindMatchCountOracleTests {
    /// `document` is the fixture page: three visible text matches plus one each in an input's value and a textarea, which WebKit's find searches, and matches it must skip — `display: none`, the `hidden` attribute, `visibility: hidden` and script source.
    private static let document = """
    <!doctype html>
    <html><body>
    <p>vendor alpha</p>
    <p>vendor beta vendor</p>
    <div style="display: none">vendor display none</div>
    <div hidden>vendor hidden attribute</div>
    <div style="visibility: hidden">vendor visibility hidden</div>
    <input value="vendor input value">
    <textarea>vendor textarea text</textarea>
    <script>var note = "vendor in script";</script>
    </body></html>
    """

    @Test(arguments: ["vendor", "VENDOR"])
    func `The bundled script's count agrees with WebKit's own find`(query: String) async throws {
        let counts = try await FindMatchCountProbe.counts(inDocument: Self.document, forQuery: query)
        let scriptCount = try #require(counts.script)
        #expect(counts.webkit == scriptCount)
    }
}
