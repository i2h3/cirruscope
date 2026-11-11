// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `AppPasswordVerdict` is what one authenticated request learned about whether the server still accepts the stored app password.
enum AppPasswordVerdict: Equatable, Sendable {
    /// `accepted` means the server answered an authenticated request successfully, so it accepts the app password.
    case accepted

    /// `rejected` means the server answered an authenticated request with HTTP 401, so it no longer accepts the app password.
    case rejected

    /// `undetermined` means the request learned nothing about the app password, whether it failed on the network, was cancelled, or was answered with anything other than success or HTTP 401.
    case undetermined

    /// `signsOut(askedAbout:signedIn:)` is whether this verdict, asked about the credentials of `askedAbout`, signs out `signedIn`, the account signed in by the time it arrived.
    ///
    /// Only a refusal signs out, and only the account it was asked about: a verdict that arrives after a sign-out, or after a sign-in to another account or with fresh credentials, says nothing about the credentials in use now.
    func signsOut(askedAbout: ServerAccount, signedIn: ServerAccount?) -> Bool {
        self == .rejected && askedAbout == signedIn
    }
}
