// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `SilentRetryStep` is what a web view has to do next while it works through a lapsed browser session, as `SilentRetryBudget` decides it.
///
/// Both web views act on the same steps, so neither can reach a different conclusion from the same events than the other.
/// Only `signOut` ends the account, and `SilentRetryBudget` only ever answers it once the server itself has refused the app password.
///
enum SilentRetryStep: Equatable {
    /// `retry` means the stale page is to be stopped and the carried address re-requested with the stored app password attached.
    case retry(URL)

    /// `confirmAppPassword` means the server is to be asked directly whether it still accepts the stored app password, the carried address being the page to return to.
    case confirmAppPassword(URL)

    /// `wait` means there is nothing to do now, because recovery is already under way, on hold, or not concerned.
    ///
    /// It says nothing about the navigation or response that asked: a caller decides that as it otherwise would, which for a redirect to the sign-in form is always to cancel it and for a response is to let it through.
    case wait

    /// `hold` means the account is kept but silent retries of the carried address stop for the carried duration, because the server could not be reached or the page could not be restored often enough in a row.
    case hold(URL, for: Duration)

    /// `signOut` means the server answered HTTP 401 to a request carrying the stored app password, so the account has to sign in again.
    case signOut
}
