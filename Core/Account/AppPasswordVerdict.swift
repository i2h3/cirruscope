// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `AppPasswordVerdict` is what one authenticated request learned about whether the server still accepts the stored app password.
///
/// It exists so that signing a user out rests on the server's word rather than on an inference: only `rejected` is that word, an HTTP 401 answered to a request that carried the app password.
/// Everything that is not that answer is `undetermined` rather than either of the other two, because a timeout, a captive portal or a server in maintenance says nothing about the credential, and treating one as a rejection is exactly how a working account gets signed out.
///
enum AppPasswordVerdict: Equatable, Sendable {
    /// `accepted` means the server answered an authenticated request successfully, so it accepts the app password.
    case accepted

    /// `rejected` means the server answered an authenticated request with HTTP 401, so it no longer accepts the app password.
    case rejected

    /// `undetermined` means the request learned nothing about the app password, whether it failed on the network, was cancelled, or was answered with anything other than success or HTTP 401.
    case undetermined

    ///
    /// `signsOut(askedAbout:signedIn:)` is whether this verdict, asked about the credentials of `askedAbout`, signs out `signedIn`, the account signed in by the time it arrived.
    ///
    /// Only a refusal signs out, and only the account it was asked about: a verdict that arrives after a sign-out, or after a sign-in to another account or with fresh credentials, says nothing about the credentials in use now.
    ///
    func signsOut(askedAbout: ServerAccount, signedIn: ServerAccount?) -> Bool {
        self == .rejected && askedAbout == signedIn
    }
}
