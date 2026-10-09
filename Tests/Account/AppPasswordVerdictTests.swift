// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `AppPasswordVerdictTests` covers `AppPasswordVerdict.signsOut(askedAbout:signedIn:)`, the rule that decides whether the server's answer about an app password ends the account signed in when it arrives.
///
/// It exists because the iOS foreground refresh signs out on that rule alone once the notifications endpoint has refused the app password, and both ways of getting it wrong cost the user: signing out on anything short of a refusal is the false sign-out of 2026-10-09 by another route, and acting on a refusal of credentials the app already replaced signs out an account that works.
///
struct AppPasswordVerdictTests {
    ///
    /// The account a check is asked about in most cases below.
    ///
    private static let account = ServerAccount(server: URL(string: "https://cloud.example.com")!, credentials: Credentials(user: "alice", appPassword: "first-app-password"))

    ///
    /// The same login on the same server after a fresh sign-in, which issues a new app password.
    ///
    private static let signedInAgain = ServerAccount(server: URL(string: "https://cloud.example.com")!, credentials: Credentials(user: "alice", appPassword: "second-app-password"))

    ///
    /// An account on another server.
    ///
    private static let otherServer = ServerAccount(server: URL(string: "https://other.example.com")!, credentials: Credentials(user: "alice", appPassword: "first-app-password"))

    @Test
    func `A refusal signs out the account it was asked about`() {
        #expect(AppPasswordVerdict.rejected.signsOut(askedAbout: Self.account, signedIn: Self.account))
    }

    @Test(arguments: [AppPasswordVerdict.accepted, .undetermined])
    func `Nothing short of a refusal signs anybody out`(verdict: AppPasswordVerdict) {
        #expect(verdict.signsOut(askedAbout: Self.account, signedIn: Self.account) == false)
    }

    @Test(arguments: [nil, signedInAgain, otherServer] as [ServerAccount?])
    func `A refusal of credentials no longer in use signs nobody out`(signedIn: ServerAccount?) {
        // The answer arrived after a sign-out, after a sign-in with fresh credentials, or after a sign-in elsewhere, so
        // it is about credentials the app has already let go of.
        #expect(AppPasswordVerdict.rejected.signsOut(askedAbout: Self.account, signedIn: signedIn) == false)
    }
}
