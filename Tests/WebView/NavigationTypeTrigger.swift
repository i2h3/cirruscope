// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `NavigationTypeTrigger` is one way a page loaded in `NavigationTypeProbe` is made to navigate to the connected server's sign-out route, each standing in for one way a Nextcloud page in the app can get there.
///
/// They differ in the two things WebKit could judge a navigation by: whether a link is activated or the location is assigned, and whether a user gesture is in force.
/// A script the app evaluates through `evaluateJavaScript(_:completionHandler:)` runs with a user gesture WebKit forces on every such evaluation, while the page's own timers run with none at all.
/// None of them is a real click: a test cannot synthesize the trusted event a pointer or a tap delivers, so the user choosing Nextcloud's "Log out" is approximated by the app activating that link, the nearest thing it can do.
///
enum NavigationTypeTrigger: CaseIterable, Sendable {
    ///
    /// `pageTimerAssignment` is the page's own interval timer assigning the sign-out address to `location.href` once the page has gone without input for a while, with no user gesture.
    ///
    /// It stands in for Nextcloud's session heartbeat with `auto_logout` set, `core/src/session-heartbeat.ts`, which does exactly that from a one-second interval once no mouse or touch input arrived for the session's lifetime.
    ///
    case pageTimerAssignment

    ///
    /// `evaluatedAssignment` is a script the app evaluates assigning the sign-out address to `location.href`, under the user gesture such an evaluation forces.
    ///
    case evaluatedAssignment

    ///
    /// `evaluatedLinkClick` is a script the app evaluates calling `click()` on a plain link to the sign-out route, under the user gesture such an evaluation forces.
    ///
    /// It is the nearest a test can come to the user choosing Nextcloud's own "Log out", which is a plain link with `target="_self"` that the browser follows.
    ///
    case evaluatedLinkClick

    ///
    /// `pageTimerLinkClick` is the page's own timer calling `click()` on the same link, with no user gesture.
    ///
    /// Nothing in Nextcloud does this; it is measured because it is the one way a page could reach the route that `SignOutRequest` cannot tell from the user.
    ///
    case pageTimerLinkClick

    ///
    /// `appLoad` is the app asking the web view to load the sign-out address through `load(_:)`.
    ///
    case appLoad

    ///
    /// `evaluatedNewWindowLinkClick` is a script the app evaluates calling `click()` on a link to the sign-out route that carries `target="_blank"`, under the user gesture such an evaluation forces.
    ///
    /// It is the user choosing a sign-out link that asks for a new window, which the Mac app decides in `webView(_:createWebViewWith:for:windowFeatures:)` and the iOS app in its navigation decider.
    ///
    case evaluatedNewWindowLinkClick
}
