// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

///
/// `NavigationTypeOutcome` is what `NavigationTypeProbe` recorded of one run, once the navigation to the sign-out route has reached its delegates and had a moment to be followed by anything else.
///
struct NavigationTypeOutcome: Sendable {
    ///
    /// `signOutActions` is every navigation action to the sign-out route the navigation delegate was asked to decide, in order.
    ///
    let signOutActions: [RecordedNavigationAction]

    ///
    /// `signOutWindowRequests` is the navigation type of every request to open the sign-out route in a new window that reached the UI delegate's `webView(_:createWebViewWith:for:windowFeatures:)`, in order.
    ///
    let signOutWindowRequests: [WKNavigationType]

    ///
    /// `requestedPaths` is the path of every document the scheme handler was asked for, in the order the requests arrived.
    ///
    let requestedPaths: [String]

    ///
    /// `contentProcessTerminations` is how often the web content process ended during the run, which would leave every other observation meaningless.
    ///
    let contentProcessTerminations: Int
}
