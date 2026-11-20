// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `FindBarViewController` is the view controller of the storyboard "Find Bar Window" scene: it owns the find bar's search field, match count and stepping buttons, and drives WebKit's own in-page search in `webView` — the Edit menu's Find items and the bar's controls all end up in `performFind(backwards:fromQueryChange:)`, which asks `webView` to highlight every match of the query and scroll to the next one in the search direction.
final class FindBarViewController: NSViewController {
    /// `webView` is the web view whose page is searched, read from the `FindBarWindowController` owning this panel on each use, because the storyboard loads the scene — and so runs `windowDidLoad` — before `WebViewController` can hand the controller its web view.
    private var webView: WKWebView? {
        (view.window?.windowController as? FindBarWindowController)?.webView
    }

    /// `findField` is the find bar's search field, which sends `findQueryChanged(_:)` on every keystroke.
    @IBOutlet
    private var findField: NSSearchField!

    /// `findCountLabel` is the find bar's label reporting which match of the page's total matches is currently highlighted, e.g. "1 of 3".
    @IBOutlet
    private var findCountLabel: NSTextField!

    /// `currentMatchIndex` is the 1-based number of the match the last find stepped to, tracked here because `WKFindResult` reports only whether a match was found, not which one; 0 while the query has no match.
    private var currentMatchIndex = 0

    /// `matchCount` is the page-wide number of matches of the current query as counted by the last find.
    private var matchCount = 0

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

    /// `showFindBar(_:)` backs the Edit menu's "Find…" item while the find panel is key: it makes the panel key, moves first responder to `findField` with its text selected so typing replaces it, and re-runs the current query so its highlights are restored.
    @IBAction
    func showFindBar(_: Any?) {
        view.window?.makeKeyAndOrderFront(nil)
        findField.delegate = self
        view.window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
        performFind(backwards: false, fromQueryChange: true)
    }

    /// `hideFindBar(_:)` closes the panel and hands first responder back to the web view; the search field's Escape key calls it.
    func hideFindBar(_: Any?) {
        view.window?.orderOut(nil)

        if let webView {
            webView.window?.makeFirstResponder(webView)
        }
    }

    /// `findQueryChanged(_:)` is sent by `findField` on every keystroke and searches the page for the field's current text.
    @IBAction
    func findQueryChanged(_: Any?) {
        logger.debug("Find query changed, \(self.findField?.stringValue.count ?? 0) character(s) (FindBarViewController)")
        performFind(backwards: false, fromQueryChange: true)
    }

    /// `findNext(_:)` backs the Edit menu's "Find Next" item and the bar's down button, stepping to the next match.
    @IBAction
    func findNext(_: Any?) {
        performFind(backwards: false, fromQueryChange: false)
    }

    /// `findPrevious(_:)` backs the Edit menu's "Find Previous" item and the bar's up button, stepping to the previous match.
    @IBAction
    func findPrevious(_: Any?) {
        performFind(backwards: true, fromQueryChange: false)
    }

    /// `performFind(backwards:fromQueryChange:)` asks `webView` to find `findField`'s text, scrolling to the next match in the search direction and updating `findCountLabel` with the result; a query change restarts at the first match while stepping wraps around the page's match count, and an empty query clears the label instead of searching.
    private func performFind(backwards: Bool, fromQueryChange: Bool) {
        guard let query = findField?.stringValue, query.isEmpty == false else {
            currentMatchIndex = 0
            matchCount = 0
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

        if fromQueryChange || matchCount == 0 {
            currentMatchIndex = 1
        } else if backwards {
            currentMatchIndex = (currentMatchIndex - 2 + matchCount) % matchCount + 1
        } else {
            currentMatchIndex = currentMatchIndex % matchCount + 1
        }

        Task {
            do {
                let result = try await webView.find(query, configuration: configuration)
                logger.debug("Find returned matchFound=\(result.matchFound, privacy: .public) (FindBarViewController)")
                let countedMatches = await countMatches(of: query, in: webView)
                logger.debug("Counted \(countedMatches) match(es) in the page (FindBarViewController)")
                updateFindCount(result, matchCount: countedMatches)
            } catch {
                logger.notice("In-page find failed: \(error.localizedDescription, privacy: .public) (FindBarViewController)")
            }
        }
    }

    /// `updateFindCount(_:matchCount:)` renders `result` and the page-wide `matchCount` into `findCountLabel` and enables the stepping buttons exactly when the query matched something.
    private func updateFindCount(_ result: WKFindResult, matchCount: Int) {
        self.matchCount = matchCount

        if result.matchFound == false {
            currentMatchIndex = 0
        }

        findCountLabel?.stringValue = Self.matchCountText(matchFound: result.matchFound, currentMatch: currentMatchIndex, matchCount: matchCount)
        findPreviousButton?.isEnabled = result.matchFound
        findNextButton?.isEnabled = result.matchFound
    }

    /// `matchCountText(matchFound:currentMatch:matchCount:)` renders a find result for the find bar's label: "No Matches" when the query matched nothing, "N of M" with the current match and the page-wide count when it did, and an empty string when the count could not be determined.
    static func matchCountText(matchFound: Bool, currentMatch: Int, matchCount: Int) -> String {
        guard matchFound else {
            return String(localized: "No Matches", comment: "Find bar label shown when the search text matches nothing on the page.")
        }

        guard matchCount > 0 else {
            return ""
        }

        return String(localized: "\(currentMatch) of \(matchCount)", comment: "Find bar label showing which match of the page's total matches is currently highlighted, e.g. \"1 of 3\".")
    }

    /// `matchCountQuery` is the function body that counts the query's occurrences in the page's rendered text, or `nil` when the bundled script is missing; the arguments dictionary's keys become the function's parameter names, so the body reads `query` directly.
    private static var matchCountQuery: String? {
        guard let source = macOSScript.findMatchCount.source else {
            return nil
        }

        return "\(source)\nreturn window.Cirruscope.findMatchCount(query);"
    }

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
