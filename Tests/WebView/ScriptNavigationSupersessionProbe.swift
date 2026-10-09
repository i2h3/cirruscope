// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import WebKit

///
/// `ScriptNavigationSupersessionProbe` measures what a real `WKWebView` does with a load the app asked for, and has not yet decided the navigation policy of, when the page that load would replace navigates itself in the meantime.
///
/// It loads a page, then asks for a second load as the app does when it re-requests a page with the app password, and holds that load's navigation-action decision instead of answering it, which is what a busy main thread does to the app's own.
/// While the decision is held, the page can be made to navigate itself to the sign-in form, which the delegate cancels as the app cancels it; the held decision is then answered with `.allow`.
/// It records every document the scheme handler is asked for, every navigation action the delegate is asked to decide, and every delegate call naming the held load's `WKNavigation`.
/// The documents are answered from memory by a `RecordingURLSchemeHandler` rather than by a server, so no network is involved, and the web view's data store is a non-persistent one, so nothing is kept.
///
@MainActor
final class ScriptNavigationSupersessionProbe: NSObject, WKNavigationDelegate {
    ///
    /// `origin` is the scheme and host every document is served under.
    ///
    private static let origin = "\(RecordingURLSchemeHandler.scheme)://cloud.example.com"

    ///
    /// `pagePath` is the path of the page loaded first, the one whose session has lapsed.
    ///
    private static let pagePath = "/page"

    ///
    /// `retryPath` is the path of the load whose decision is held, standing in for the app's re-request of the page with the app password.
    ///
    private static let retryPath = "/retry"

    ///
    /// `signInPath` is the path of the sign-in form the page sends itself to, which the delegate cancels.
    ///
    private static let signInPath = "/login"

    ///
    /// `pollPath` is the path the page polls, as Nextcloud's pages poll the server.
    ///
    private static let pollPath = "/status"

    ///
    /// `stepTimeout` is how long a step that has to happen is waited for before the run fails.
    ///
    /// It is generous because every callback recorded here arrives on the main actor, which is shared with every other suite in the run, and because the first load in a run also launches a web content process.
    /// On a Mac whose load average stood above 50, the first page loaded in an iOS Simulator took longer than a minute to finish.
    ///
    private static let stepTimeout: Duration = .seconds(120)

    ///
    /// `observationWindow` is how long the held load is given, once its decision has been answered, to show any sign of happening.
    ///
    /// It is the one bounded wait whose expiry is not a failure, since proving that something does not happen takes waiting for it.
    /// The control case, whose held load does go ahead, has to finish within the same window, which is what makes an empty record at its end mean something.
    ///
    private static let observationWindow: Duration = .seconds(10)

    ///
    /// `document` is the HTML every document is answered with: a page that polls, and that goes to the sign-in form, once, on the first poll answered with HTTP 401.
    ///
    /// That is what Nextcloud's `core/src/utils/xhr-request.js` does for every request of the page's that the server answers with 401 once the session behind it has lapsed.
    ///
    private static let document = """
    <!doctype html>
    <meta charset="utf-8">
    <title>Stale page</title>
    <script>
        async function poll() {
            try {
                const response = await fetch("\(pollPath)", { cache: "no-store" });

                if (response.status === 401) {
                    location.href = "\(signInPath)?redirect_url=" + encodeURIComponent(location.pathname);
                    return;
                }
            } catch {}

            setTimeout(poll, 100);
        }

        poll();
    </script>
    """

    ///
    /// `schemeHandler` serves the documents and records every request for one.
    ///
    private let schemeHandler: RecordingURLSchemeHandler

    ///
    /// `webView` is the web view the documents are loaded into.
    ///
    private let webView: WKWebView

    ///
    /// `decidedPaths` is the path of every navigation action this delegate was asked to decide, in order.
    ///
    private var decidedPaths: [String] = []

    ///
    /// `heldDecision` is the decision handler of the load to `retryPath`, kept unanswered until the run releases it.
    ///
    private var heldDecision: (@MainActor (WKNavigationActionPolicy) -> Void)?

    ///
    /// `callbacks` is every navigation delegate call naming a `WKNavigation`, together with the navigation it named, in order.
    ///
    private var callbacks: [(navigation: WKNavigation?, callback: NavigationCallback)] = []

    ///
    /// `contentProcessTerminations` is how often the web content process ended during the run.
    ///
    private var contentProcessTerminations = 0

    ///
    /// `init()` builds a web view that keeps nothing, is served by a `RecordingURLSchemeHandler`, and reports its navigations to this probe.
    ///
    override private init() {
        schemeHandler = RecordingURLSchemeHandler(document: Self.document, pollPath: Self.pollPath)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: RecordingURLSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    ///
    /// `measureHeldLoad(supersededBy:)` is what becomes of a load whose decision is held and then answered with `.allow`, after the page it would replace navigated itself to the sign-in form by `trigger` in between, or without that when `trigger` is `nil`.
    ///
    static func measureHeldLoad(supersededBy trigger: ScriptNavigationTrigger? = nil) async throws -> ScriptNavigationSupersessionOutcome {
        let probe = ScriptNavigationSupersessionProbe()

        defer {
            probe.tearDown()
        }

        return try await probe.measure(supersededBy: trigger)
    }

    ///
    /// `measure(supersededBy:)` runs the steps `measureHeldLoad(supersededBy:)` describes and answers what was recorded.
    ///
    private func measure(supersededBy trigger: ScriptNavigationTrigger?) async throws -> ScriptNavigationSupersessionOutcome {
        let pageNavigation = webView.load(URLRequest(url: url(for: Self.pagePath)))
        let pageFinished = await waitUntil { self.callbacks(of: pageNavigation).contains(.didFinish) }
        try #require(pageFinished, "The page never finished loading")

        let retryNavigation = webView.load(URLRequest(url: url(for: Self.retryPath)))
        try #require(retryNavigation != nil, "The web view did not start the load whose decision is to be held")
        let retryHeld = await waitUntil { self.heldDecision != nil }
        try #require(retryHeld, "The held load's navigation action never reached the navigation delegate")

        if let trigger {
            try await navigateToSignInForm(by: trigger)
            let signInDecided = await waitUntil { self.decidedPaths.contains(Self.signInPath) }
            try #require(signInDecided, "The page's own navigation to the sign-in form never reached the navigation delegate")
        }

        heldDecision?(.allow)
        heldDecision = nil

        // The one wait whose expiry is expected: when the held load goes ahead it ends with a final callback well inside
        // the window, and when it does not, nothing ends the wait but the window itself.
        _ = await waitUntil(timeout: Self.observationWindow) { self.callbacks(of: retryNavigation).contains(where: \.isFinal) }

        let documentPath = try await evaluate("location.pathname")
        let requestedPaths = schemeHandler.requestedPaths.filter { $0 != Self.pollPath }

        return ScriptNavigationSupersessionOutcome(requestedPaths: requestedPaths, decidedPaths: decidedPaths, heldLoadCallbacks: callbacks(of: retryNavigation), reportedPath: webView.url?.path, documentPath: documentPath, contentProcessTerminations: contentProcessTerminations)
    }

    ///
    /// `navigateToSignInForm(by:)` makes the loaded page send itself to the sign-in form in the way `trigger` names.
    ///
    private func navigateToSignInForm(by trigger: ScriptNavigationTrigger) async throws {
        switch trigger {
            case .evaluatedScript:
                _ = try await evaluate("location.href = '\(Self.signInPath)?redirect_url=%2Fpage'")

            case .rejectedPoll:
                schemeHandler.rejectsPolls = true
        }
    }

    ///
    /// `tearDown()` answers a decision still held, so WebKit does not raise an exception over a decision handler released unanswered, and stops whatever the web view is still loading.
    ///
    private func tearDown() {
        heldDecision?(.cancel)
        heldDecision = nil
        webView.stopLoading()
    }

    ///
    /// `url(for:)` is the address of the document at `path`.
    ///
    private func url(for path: String) -> URL {
        URL(string: Self.origin + path)!
    }

    ///
    /// `callbacks(of:)` is every recorded navigation delegate call naming `navigation`, in order.
    ///
    private func callbacks(of navigation: WKNavigation?) -> [NavigationCallback] {
        guard let navigation else {
            return []
        }

        return callbacks.filter { $0.navigation === navigation }.map(\.callback)
    }

    ///
    /// `waitUntil(timeout:_:)` waits for `condition` to hold, checking it again every few milliseconds so the main actor is free to deliver callbacks in between, and answers whether it held before `timeout` passed.
    ///
    private func waitUntil(timeout: Duration = ScriptNavigationSupersessionProbe.stepTimeout, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while condition() == false {
            guard ContinuousClock.now < deadline else {
                return false
            }

            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return false
            }
        }

        return true
    }

    ///
    /// `evaluate(_:)` evaluates `script` in the page and answers its result where that is a string.
    ///
    private func evaluate(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }
    }

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let path = navigationAction.request.url?.path ?? ""
        decidedPaths.append(path)

        switch path {
            case Self.retryPath where heldDecision == nil:
                heldDecision = decisionHandler

            case Self.signInPath:
                decisionHandler(.cancel)

            default:
                decisionHandler(.allow)
        }
    }

    func webView(_: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        callbacks.append((navigation, .didStartProvisionalNavigation))
    }

    func webView(_: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        callbacks.append((navigation, .didReceiveServerRedirect))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError _: any Error) {
        callbacks.append((navigation, .didFailProvisionalNavigation))
    }

    func webView(_: WKWebView, didCommit navigation: WKNavigation!) {
        callbacks.append((navigation, .didCommit))
    }

    func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        callbacks.append((navigation, .didFinish))
    }

    func webView(_: WKWebView, didFail navigation: WKNavigation!, withError _: any Error) {
        callbacks.append((navigation, .didFail))
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        contentProcessTerminations += 1
    }
}
