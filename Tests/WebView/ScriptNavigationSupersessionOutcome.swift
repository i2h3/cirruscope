// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `ScriptNavigationSupersessionOutcome` is what `ScriptNavigationSupersessionProbe` recorded of one run, once the held load has had its chance to happen.
///
struct ScriptNavigationSupersessionOutcome: Sendable {
    ///
    /// `requestedPaths` is the path of every document the scheme handler was asked for, in the order the requests arrived, leaving out the page's polls.
    ///
    let requestedPaths: [String]

    ///
    /// `decidedPaths` is the path of every navigation action the navigation delegate was asked to decide, in the order it was asked.
    ///
    let decidedPaths: [String]

    ///
    /// `heldLoadCallbacks` is every navigation delegate call naming the `WKNavigation` the held load's `load(_:)` returned, in the order they arrived.
    ///
    let heldLoadCallbacks: [NavigationCallback]

    ///
    /// `reportedPath` is the path of the URL the web view's `url` property reports at the end.
    ///
    let reportedPath: String?

    ///
    /// `documentPath` is the path of the document the web view actually shows at the end, as that document's own `location.pathname` reports it.
    ///
    let documentPath: String?

    ///
    /// `contentProcessTerminations` is how often the web content process ended during the run, which would leave every other observation meaningless.
    ///
    let contentProcessTerminations: Int
}
