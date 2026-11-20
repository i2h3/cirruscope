// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `FindBarViewController` is the view controller of the storyboard "Find Bar Window" scene: it owns the find bar's search field, match count and stepping buttons, and drives WebKit's own in-page search in `webView` — the Edit menu's Find Next and Find Previous items, the search field and the bar's buttons all end up in `performFind(backwards:)`, which asks `webView` to select the next match of the query and scroll it into view, while Find… only shows the bar and counts the current query again.
final class FindBarViewController: NSViewController {
    /// `webView` is the web view whose page is searched, read from the `FindBarWindowController` owning this panel on each use, because the storyboard loads the scene before `WebViewController` can hand the controller its web view.
    private var webView: WKWebView? {
        (view.window?.windowController as? FindBarWindowController)?.webView
    }

    /// `findField` is the find bar's search field, which sends `findQueryChanged(_:)` on every keystroke.
    @IBOutlet
    private var findField: NSSearchField!

    /// `findCountLabel` is the find bar's label reporting how many matches the current query has on the page.
    @IBOutlet
    private var findCountLabel: NSTextField!

    /// `findPreviousButton` is the find bar's up button, stepping to the previous match; disabled while the query has no matches.
    @IBOutlet
    private var findPreviousButton: NSButton!

    /// `findNextButton` is the find bar's down button, stepping to the next match; disabled while the query has no matches.
    @IBOutlet
    private var findNextButton: NSButton!

    /// `logger` records this view controller's activity under the `FindBarViewController` category.
    private let logger = Logger(for: FindBarViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()

        findPreviousButton?.isEnabled = false
        findNextButton?.isEnabled = false
    }

    /// `showFindBar(_:)` backs the Edit menu's "Find…" item: it attaches the panel to the web window, makes the panel key, moves first responder to `findField` with its text selected so typing replaces it, and re-counts the current query's matches without searching, so the label reflects the page just opened; the count cannot say whether anything matched, so only a search decides that.
    @IBAction
    func showFindBar(_: Any?) {
        (view.window?.windowController as? FindBarWindowController)?.attachToWebWindow()
        view.window?.makeKeyAndOrderFront(nil)
        findField.delegate = self
        view.window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)

        guard let webView else {
            return
        }

        let query = findField.stringValue
        guard query.isEmpty == false else {
            return
        }

        Task {
            let count = await countMatches(of: query, in: webView)
            guard findField.stringValue == query else {
                return
            }
            updateFindCount(matchFound: true, matchCount: count)
        }
    }

    /// `hideFindBar(_:)` closes the panel and hands first responder back to the web view; the search field's Escape key calls it.
    func hideFindBar(_: Any?) {
        view.window?.orderOut(nil)

        if let webView {
            webView.window?.makeFirstResponder(webView)
        }
    }

    /// `findQueryChanged(_:)` is sent by `findField` on every keystroke and searches the page for the field's current text, from the start of the current selection.
    @IBAction
    func findQueryChanged(_: Any?) {
        logger.debug("Find query changed, \(self.findField?.stringValue.count ?? 0) character(s) (FindBarViewController)")
        performFind(backwards: false)
    }

    /// `findNext(_:)` backs the Edit menu's "Find Next" item and the bar's down button, stepping to the next match; with no query in the field it shows the bar instead, so the item is never a dead key.
    @IBAction
    func findNext(_: Any?) {
        guard findField.stringValue.isEmpty == false else {
            showFindBar(nil)
            return
        }
        performFind(backwards: false)
    }

    /// `findPrevious(_:)` backs the Edit menu's "Find Previous" item and the bar's up button, stepping to the previous match; with no query in the field it shows the bar instead, so the item is never a dead key.
    @IBAction
    func findPrevious(_: Any?) {
        guard findField.stringValue.isEmpty == false else {
            showFindBar(nil)
            return
        }
        performFind(backwards: true)
    }

    /// `performFind(backwards:)` asks `webView` to find `findField`'s text, scrolling to the next match in the search direction and updating `findCountLabel` with the result; an empty query clears the label instead of searching.
    private func performFind(backwards: Bool) {
        guard let query = findField?.stringValue, query.isEmpty == false else {
            findCountLabel?.stringValue = ""
            findPreviousButton?.isEnabled = false
            findNextButton?.isEnabled = false
            return
        }

        guard let webView else {
            logger.notice("Find bar has no web view to search (FindBarViewController)")
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true

        logger.debug("Finding \(query.count) character(s), backwards=\(backwards, privacy: .public) (FindBarViewController)")

        Task {
            do {
                let result = try await webView.find(query, configuration: configuration)
                logger.debug("Find returned matchFound=\(result.matchFound, privacy: .public) (FindBarViewController)")
                let matchCount = await countMatches(of: query, in: webView)
                logger.debug("Counted \(matchCount) match(es) in the page (FindBarViewController)")
                guard findField.stringValue == query else {
                    return
                }
                updateFindCount(matchFound: result.matchFound, matchCount: matchCount)
            } catch {
                logger.notice("In-page find failed: \(error.localizedDescription, privacy: .public) (FindBarViewController)")
            }
        }
    }

    /// `updateFindCount(matchFound:matchCount:)` renders whether the query matched and the page-wide `matchCount` into `findCountLabel` and enables the stepping buttons exactly when the query matched something.
    private func updateFindCount(matchFound: Bool, matchCount: Int) {
        findCountLabel?.stringValue = Self.matchCountText(matchFound: matchFound, matchCount: matchCount)
        findPreviousButton?.isEnabled = matchFound
        findNextButton?.isEnabled = matchFound
    }

    /// `matchCountText(matchFound:matchCount:)` renders a find result for the find bar's label: "No Matches" when the query matched nothing, "N matches" with the page-wide count when it did, and an empty string when the count could not be determined.
    static func matchCountText(matchFound: Bool, matchCount: Int) -> String {
        guard matchFound else {
            return String(localized: "No Matches", comment: "Find bar label shown when the search text matches nothing on the page.")
        }

        guard matchCount > 0 else {
            return ""
        }

        return String(localized: "\(matchCount) matches", comment: "Find bar label showing how many times the search text occurs on the page.")
    }

    /// `matchCountQuery` is the function body that counts the query's occurrences in the page's rendered text, or `nil` when the bundled script is missing; the arguments dictionary's keys become the function's parameter names, so the body reads `query` directly. Internal so `FindMatchCountOracleTests` can run the same body against a real web view.
    static let matchCountQuery: String? = macOSScript.findMatchCount.source.map { "\($0)\nreturn window.Cirruscope.findMatchCount(query);" }

    /// `countMatches(of:in:)` asks the page how many times `query` occurs in its rendered text, answering 0 when the bundled script is missing or the query fails.
    private func countMatches(of query: String, in webView: WKWebView) async -> Int {
        guard let functionBody = Self.matchCountQuery else {
            return 0
        }

        do {
            let result = try await webView.callAsyncJavaScript(functionBody, arguments: ["query": query], in: nil, contentWorld: .page)
            logger.debug("Match count script returned \(String(describing: result), privacy: .public) (FindBarViewController)")
            return result as? Int ?? 0
        } catch {
            logger.notice("Counting in-page matches failed: \(error.localizedDescription, privacy: .public) (FindBarViewController)")
            return 0
        }
    }
}

extension FindBarViewController: NSSearchFieldDelegate {
    /// `control(_:textView:doCommandBy:)` closes the find bar on Escape, which the search field forwards as `cancelOperation`.
    func control(_: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }

        hideFindBar(nil)
        return true
    }
}
