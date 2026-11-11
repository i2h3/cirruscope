// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ScriptNavigationTrigger` is how the stale page `ScriptNavigationSupersessionProbe` loads is made to send itself to the sign-in form while the app's own load waits for its navigation policy.
enum ScriptNavigationTrigger: CaseIterable, Sendable {
    /// `evaluatedScript` is the app evaluating an assignment to `location.href` in the page.
    case evaluatedScript

    /// `rejectedPoll` is the page's own poll being answered with HTTP 401, which its script answers by assigning `location.href`, as Nextcloud's `core/src/utils/xhr-request.js` does for every 401 a request of the page's receives.
    case rejectedPoll
}
