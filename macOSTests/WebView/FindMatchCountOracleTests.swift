// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Testing

/// `FindMatchCountOracleTests` asserts that the bundled match-count script agrees with WebKit's own `find(_:configuration:)` on a fixture page holding visible, hidden, form, iframe, shadow-root and script text, and that a longer query does not move the start of the page's selection, both measured in a real `WKWebView` through `FindMatchCountProbe` (issue #98).
@MainActor
@Suite(.timeLimit(.minutes(5)))
struct FindMatchCountOracleTests {
    /// `document` is the fixture page: three visible text matches plus one each in a text input, a textarea, a rendered same-origin iframe, an open shadow root, text placed directly in a shadow root, a `display: contents` span, a visible `display: contents` span inside a `visibility: hidden` element and an empty slot's fallback text, which WebKit's find searches, and matches it must skip — `display: none`, the `hidden` attribute, `visibility: hidden`, an iframe in a hidden element, an unslotted child of a shadow host, a filled slot's fallback text, script source and the values of non-text controls (checkbox, radio, password, submit, date).
    private static let document = """
    <!doctype html>
    <html><body>
    <p>vendor alpha</p>
    <p>vendor beta vendor</p>
    <div style="display: none">vendor display none</div>
    <div hidden>vendor hidden attribute</div>
    <div style="visibility: hidden">vendor visibility hidden</div>
    <input value="vendor text input">
    <textarea>vendor textarea text</textarea>
    <input type="checkbox" value="vendor checkbox">
    <input type="radio" value="vendor radio">
    <input type="password" value="vendor password">
    <input type="submit" value="vendor submit">
    <input type="date" value="2026-11-20">
    <iframe srcdoc="<p>vendor iframe</p>"></iframe>
    <div style="display: none"><iframe srcdoc="<p>vendor hidden frame</p>"></iframe></div>
    <span style="display: contents">vendor contents</span>
    <div style="visibility: hidden"><span style="display: contents; visibility: visible">vendor visible again</span></div>
    <div id="host"></div>
    <div id="bare"></div>
    <div id="lighthost">vendor unslotted</div>
    <div id="filled"><span>other</span></div>
    <div id="empty"></div>
    <script>var note = "vendor in script"; document.getElementById("host").attachShadow({ mode: "open" }).innerHTML = "<p>vendor shadow</p>"; document.getElementById("bare").attachShadow({ mode: "open" }).textContent = "vendor bare shadow"; document.getElementById("lighthost").attachShadow({ mode: "open" }).innerHTML = "<p>other</p>"; document.getElementById("filled").attachShadow({ mode: "open" }).innerHTML = "<slot>vendor fallback</slot>"; document.getElementById("empty").attachShadow({ mode: "open" }).innerHTML = "<slot>vendor fallback shown</slot>";</script>
    </body></html>
    """

    @Test(arguments: ["vendor", "VENDOR", "2026"])
    func `The bundled script's count agrees with WebKit's own find`(query: String) async throws {
        let counts = try await FindMatchCountProbe.counts(inDocument: Self.document, forQuery: query)
        let scriptCount = try #require(counts.script)
        #expect(counts.webkit == scriptCount)
    }

    /// Searching a longer query starts from the start of the current selection, so the selection's start does not move between the two finds.
    @Test
    func `Searching a longer query does not move the start of the selection`() async throws {
        let starts = try await FindMatchCountProbe.selectionStarts(inDocument: Self.document, afterFinds: ["ve", "ven"])
        let first = try #require(starts.first)
        #expect(first >= 0)
        #expect(starts.count == 2)
        #expect(starts.allSatisfy { $0 == first })
    }
}
