// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Synchronization

///
/// `KeychainStandIn` answers who is signed in for a `ServerNotificationLedger` under test, in place of the real Keychain, which holds the developer's own credentials.
///
/// A case signs accounts in and out of it, or makes it refuse to answer, between the steps it takes, which is how a sign-out landing in the middle of a fetch is staged without touching anything real.
///
final class KeychainStandIn: Sendable {
    ///
    /// `Refusal` is the error the stand-in throws while it refuses to answer, as a locked Keychain would.
    ///
    struct Refusal: Error {}

    ///
    /// `stored` is the credentials signed in, keyed by the server they sign in to.
    ///
    private let stored: Mutex<[URL: Credentials]>

    ///
    /// `refuses` is whether every read throws, as the real Keychain does while it cannot be read.
    ///
    private let refuses = Mutex(false)

    ///
    /// `init(signedIn:)` starts the stand-in with `accounts` signed in.
    ///
    init(signedIn accounts: [ServerAccount] = []) {
        stored = Mutex(Dictionary(accounts.map { ($0.server, $0.credentials) }, uniquingKeysWith: { _, last in last }))
    }

    ///
    /// `signIn(_:)` stores `account`'s credentials, replacing any for its server.
    ///
    func signIn(_ account: ServerAccount) {
        stored.withLock { $0[account.server] = account.credentials }
    }

    ///
    /// `signOut()` forgets every stored credential, as a sign-out's `Keychain.clearAll()` does.
    ///
    func signOut() {
        stored.withLock { $0.removeAll() }
    }

    ///
    /// `refuse(_:)` makes every read throw while `refusing` is `true`.
    ///
    func refuse(_ refusing: Bool) {
        refuses.withLock { $0 = refusing }
    }

    ///
    /// `credentials(for:)` is the credentials stored for `server`, or `nil` when none are, throwing while the stand-in refuses to answer.
    ///
    func credentials(for server: URL) throws -> Credentials? {
        guard refuses.withLock({ $0 }) == false else {
            throw Refusal()
        }

        return stored.withLock { $0[server] }
    }
}
