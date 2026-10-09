// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `NavigationCallback` is one of the `WKNavigationDelegate` calls that name the `WKNavigation` they report on, as `ScriptNavigationSupersessionProbe` records them.
///
/// They are every way a web view tells its delegate what became of a navigation it was asked for, so a navigation that receives none of them is one whose fate its delegate never learns.
///
enum NavigationCallback: Equatable, Sendable {
    ///
    /// `didStartProvisionalNavigation` is `webView(_:didStartProvisionalNavigation:)`, the request for the new document having gone out.
    ///
    case didStartProvisionalNavigation

    ///
    /// `didReceiveServerRedirect` is `webView(_:didReceiveServerRedirectForProvisionalNavigation:)`, the request having been redirected before anything was committed.
    ///
    case didReceiveServerRedirect

    ///
    /// `didFailProvisionalNavigation` is `webView(_:didFailProvisionalNavigation:withError:)`, the navigation having ended before its document was committed.
    ///
    case didFailProvisionalNavigation

    ///
    /// `didCommit` is `webView(_:didCommit:)`, the new document having replaced the old one.
    ///
    case didCommit

    ///
    /// `didFinish` is `webView(_:didFinish:)`, the new document having finished loading.
    ///
    case didFinish

    ///
    /// `didFail` is `webView(_:didFail:withError:)`, the navigation having ended after its document was committed.
    ///
    case didFail

    ///
    /// `isFinal` is whether no further callback follows this one for the same navigation.
    ///
    var isFinal: Bool {
        switch self {
            case .didFailProvisionalNavigation, .didFinish, .didFail:
                true

            case .didStartProvisionalNavigation, .didReceiveServerRedirect, .didCommit:
                false
        }
    }
}
