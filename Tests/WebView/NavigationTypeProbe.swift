// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import WebKit

///
/// `NavigationTypeProbe` measures the `WKNavigationType` a real `WKWebView` reports for a navigation to the connected server's sign-out route, for each way such a navigation can begin.
///
/// It loads a page holding two links to the route, one plain and one carrying `target="_blank"`, and makes the page navigate to it in the way a `NavigationTypeTrigger` names.
/// It records every navigation action to the route that its navigation delegate is asked to decide, together with the frame the action targets, and every request to open the route in a new window that reaches its UI delegate.
/// A main-frame action to the route is cancelled, so the page never leaves and the stand-in server never sees the request; a new-window action is allowed, as the Mac app's navigation delegate allows it, so that it goes on to the UI delegate, which answers it with `nil` and so opens nothing.
/// The documents are answered from memory by a `RecordingURLSchemeHandler` rather than by a server, so no network is involved, and the web view's data store is a non-persistent one, so nothing is kept.
/// What it cannot do is click: a test has no way to deliver the trusted event a pointer or a tap produces, so the user choosing a link is approximated by a script the app evaluates calling the link's `click()`.
///
@MainActor
final class NavigationTypeProbe: NSObject, WKNavigationDelegate, WKUIDelegate {
    ///
    /// `origin` is the scheme and host every document is served under, standing in for the connected server.
    ///
    private static let origin = "\(RecordingURLSchemeHandler.scheme)://cloud.example.com"

    ///
    /// `pagePath` is the path of the page loaded first, the signed-in page the navigation leaves from.
    ///
    private static let pagePath = "/page"

    ///
    /// `signOutPath` is the path of Nextcloud's sign-out route, which every trigger navigates to.
    ///
    private static let signOutPath = "/logout"

    ///
    /// `signOutAddress` is the address every trigger navigates to, the sign-out route with the request token Nextcloud appends to it.
    ///
    private static let signOutAddress = "\(signOutPath)?requesttoken=x"

    ///
    /// `stepTimeout` is how long a step that has to happen is waited for before the run fails.
    ///
    /// It is as generous as `ScriptNavigationSupersessionProbe`'s, for the same reason: every callback recorded here arrives on the main actor shared with every other suite in the run, and the first load in a run also launches a web content process.
    ///
    private static let stepTimeout: Duration = .seconds(120)

    ///
    /// `settlingTime` is how long the run goes on recording once the navigation has reached a delegate that settles it, so that anything WebKit does after it is recorded rather than missed.
    ///
    /// It is the one wait whose expiry is not a failure, since proving that nothing follows takes waiting for it.
    ///
    private static let settlingTime: Duration = .seconds(1)

    ///
    /// `trigger` is how this run makes the page navigate to the sign-out route.
    ///
    private let trigger: NavigationTypeTrigger

    ///
    /// `schemeHandler` serves the page and records every request for a document.
    ///
    private let schemeHandler: RecordingURLSchemeHandler

    ///
    /// `webView` is the web view the page is loaded into.
    ///
    private let webView: WKWebView

    ///
    /// `pageNavigation` is the navigation that loads the page, once it has been asked for.
    ///
    private var pageNavigation: WKNavigation?

    ///
    /// `pageFinished` is whether the page has finished loading.
    ///
    private var pageFinished = false

    ///
    /// `signOutActions` is every navigation action to the sign-out route the navigation delegate was asked to decide, in order.
    ///
    private var signOutActions: [RecordedNavigationAction] = []

    ///
    /// `signOutWindowRequests` is the navigation type of every request to open the sign-out route in a new window, in order.
    ///
    private var signOutWindowRequests: [WKNavigationType] = []

    ///
    /// `contentProcessTerminations` is how often the web content process ended during the run.
    ///
    private var contentProcessTerminations = 0

    ///
    /// `init(trigger:)` builds a web view that keeps nothing, is served a page made to navigate by `trigger`, and reports its navigations and its new-window requests to this probe.
    ///
    private init(trigger: NavigationTypeTrigger) {
        self.trigger = trigger
        schemeHandler = RecordingURLSchemeHandler(document: Self.document(for: trigger))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: RecordingURLSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    ///
    /// `measure(_:)` is what the navigation delegate and the UI delegate are told of a navigation to the sign-out route that `trigger` began.
    ///
    static func measure(_ trigger: NavigationTypeTrigger) async throws -> NavigationTypeOutcome {
        let probe = NavigationTypeProbe(trigger: trigger)

        defer {
            probe.tearDown()
        }

        return try await probe.measure()
    }

    ///
    /// `document(for:)` is the page served for `trigger`: the two links to the sign-out route, and, for a trigger the page carries out itself, the script that does it.
    ///
    /// The page's own script is armed by its `load` event and waits a moment longer, so that it runs without a user gesture and only after the page has finished loading.
    ///
    private static func document(for trigger: NavigationTypeTrigger) -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>Signed-in page</title>
        <a id="sign-out" href="\(signOutAddress)">Log out</a>
        <a id="sign-out-in-new-window" href="\(signOutAddress)" target="_blank">Log out in a new window</a>
        <script>
        \(pageScript(for: trigger))
        </script>
        """
    }

    ///
    /// `pageScript(for:)` is the script the page runs of its own accord for `trigger`, which is nothing for a trigger the app carries out.
    ///
    private static func pageScript(for trigger: NavigationTypeTrigger) -> String {
        switch trigger {
            case .pageTimerAssignment:
                // The shape of Nextcloud's `core/src/session-heartbeat.ts` with `auto_logout` set, compressed from
                // a one-second interval and the session's lifetime to a few milliseconds, and cleared after it fires
                // so that it navigates once rather than once per tick.
                """
                addEventListener("load", () => {
                    const lastActive = Date.now();
                    const heartbeat = setInterval(() => {
                        if (Date.now() - lastActive > 250) {
                            clearInterval(heartbeat);
                            window.location.href = "\(signOutAddress)";
                        }
                    }, 50);
                });
                """

            case .pageTimerLinkClick:
                """
                addEventListener("load", () => {
                    setTimeout(() => document.getElementById("sign-out").click(), 250);
                });
                """

            case .evaluatedAssignment, .evaluatedLinkClick, .appLoad, .evaluatedNewWindowLinkClick:
                ""
        }
    }

    ///
    /// `measure()` runs the steps `measure(_:)` describes and answers what was recorded.
    ///
    private func measure() async throws -> NavigationTypeOutcome {
        pageNavigation = webView.load(URLRequest(url: url(for: Self.pagePath)))
        let pageLoaded = await waitUntil { self.pageFinished }
        try #require(pageLoaded, "The page never finished loading")

        try await navigateToSignOutRoute()

        let settled = await waitUntil { self.isSettled }
        try #require(settled, "The navigation to the sign-out route never reached a delegate as a frame's navigation or a new-window request; the navigation delegate recorded \(signOutActions)")

        // The one wait whose expiry is expected: nothing is meant to follow, and only waiting shows that nothing did.
        try await Task.sleep(for: Self.settlingTime)

        return NavigationTypeOutcome(signOutActions: signOutActions, signOutWindowRequests: signOutWindowRequests, requestedPaths: schemeHandler.requestedPaths, contentProcessTerminations: contentProcessTerminations)
    }

    ///
    /// `isSettled` is whether the navigation to the sign-out route has reached a delegate that ends it here: the navigation delegate deciding it for a frame, which this probe cancels, or the UI delegate being asked for a new window, which it refuses.
    ///
    /// A new-window action reaching the navigation delegate does not settle it, being allowed on to the UI delegate.
    ///
    private var isSettled: Bool {
        signOutActions.contains { $0.target != .newWindow } || signOutWindowRequests.isEmpty == false
    }

    ///
    /// `navigateToSignOutRoute()` does what the app does for `trigger`, which is nothing where the page's own script navigates.
    ///
    private func navigateToSignOutRoute() async throws {
        switch trigger {
            case .pageTimerAssignment, .pageTimerLinkClick:
                break

            case .evaluatedAssignment:
                try await evaluate("window.location.href = \"\(Self.signOutAddress)\"; true")

            case .evaluatedLinkClick:
                try await evaluate("document.getElementById(\"sign-out\").click(); true")

            case .appLoad:
                webView.load(URLRequest(url: url(for: Self.signOutAddress)))

            case .evaluatedNewWindowLinkClick:
                try await evaluate("document.getElementById(\"sign-out-in-new-window\").click(); true")
        }
    }

    ///
    /// `tearDown()` stops whatever the web view is still loading.
    ///
    private func tearDown() {
        webView.stopLoading()
    }

    ///
    /// `url(for:)` is the address of `pathAndQuery` on the probe's origin.
    ///
    private func url(for pathAndQuery: String) -> URL {
        URL(string: Self.origin + pathAndQuery)!
    }

    ///
    /// `target(of:)` is the frame `navigationAction` would load into.
    ///
    private static func target(of navigationAction: WKNavigationAction) -> NavigationActionTarget {
        guard let targetFrame = navigationAction.targetFrame else {
            return .newWindow
        }

        return targetFrame.isMainFrame ? .mainFrame : .subFrame
    }

    ///
    /// `waitUntil(timeout:_:)` waits for `condition` to hold, checking it again every few milliseconds so the main actor is free to deliver callbacks in between, and answers whether it held before `timeout` passed.
    ///
    private func waitUntil(timeout: Duration = NavigationTypeProbe.stepTimeout, _ condition: () -> Bool) async -> Bool {
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
    /// `evaluate(_:)` evaluates `script` in the page through `evaluateJavaScript(_:completionHandler:)`, which runs it under a user gesture WebKit forces on every such evaluation.
    ///
    private func evaluate(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    ///
    /// `webView(_:decidePolicyFor:decisionHandler:)` records a navigation action to the sign-out route with the frame it targets, cancels it where it targets a frame, and allows everything else, a new-window request to the route included.
    ///
    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url?.path == Self.signOutPath else {
            decisionHandler(.allow)
            return
        }

        let target = Self.target(of: navigationAction)
        signOutActions.append(RecordedNavigationAction(navigationType: navigationAction.navigationType, target: target))

        decisionHandler(target == .newWindow ? .allow : .cancel)
    }

    ///
    /// `webView(_:didFinish:)` notes that the page has finished loading.
    ///
    func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === pageNavigation {
            pageFinished = true
        }
    }

    ///
    /// `webViewWebContentProcessDidTerminate(_:)` counts the web content process ending.
    ///
    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        contentProcessTerminations += 1
    }

    ///
    /// `webView(_:createWebViewWith:for:windowFeatures:)` records a request to open the sign-out route in a new window and refuses every request by answering `nil`, so no window is ever opened.
    ///
    func webView(_: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        if navigationAction.request.url?.path == Self.signOutPath {
            signOutWindowRequests.append(navigationAction.navigationType)
        }

        return nil
    }
}
