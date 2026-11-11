// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NavigationTypeTrigger` is one way a page loaded in `NavigationTypeProbe` is made to navigate to the connected server's sign-out route, each standing in for one way a Nextcloud page in the app can get there.
enum NavigationTypeTrigger: CaseIterable, Sendable {
    /// `pageTimerAssignment` is the page's own interval timer assigning the sign-out address to `location.href` once the page has gone without input for a while, with no user gesture.
    case pageTimerAssignment

    /// `evaluatedAssignment` is a script the app evaluates assigning the sign-out address to `location.href`, under the user gesture such an evaluation forces.
    case evaluatedAssignment

    /// `evaluatedLinkClick` is a script the app evaluates calling `click()` on a plain link to the sign-out route, under the user gesture such an evaluation forces.
    case evaluatedLinkClick

    /// `pageTimerLinkClick` is the page's own timer calling `click()` on the same link, with no user gesture.
    case pageTimerLinkClick

    /// `appLoad` is the app asking the web view to load the sign-out address through `load(_:)`.
    case appLoad

    /// `evaluatedNewWindowLinkClick` is a script the app evaluates calling `click()` on a link to the sign-out route that carries `target="_blank"`, under the user gesture such an evaluation forces.
    case evaluatedNewWindowLinkClick
}
