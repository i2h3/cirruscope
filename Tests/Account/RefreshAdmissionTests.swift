// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `RefreshAdmissionTests` covers `RefreshAdmission`, which decides whether what a refresh fetched may still be written once the fetch comes back.
///
/// The suite exists because a refresh outlives the sign-out it overlaps: what it fetched used to be written regardless, which put the old server's apps, conversations, notes and collectives back into a store the sign-out had just emptied.
/// Most cases are therefore ones that must not be admitted, and the one that most needs pinning is the least obvious: signing back in to the same server stores new credentials under the same address, so a matching address alone must not be enough.
struct RefreshAdmissionTests {
    /// `server` is the server every case's refresh fetched from.
    private static let server = URL(string: "https://cloud.example.com")!

    /// `alice` is the account every case's refresh fetched as.
    private static let alice = Credentials(user: "alice", appPassword: "first-app-password")

    @Test
    func `A refresh whose account is still signed in may write what it fetched`() {
        #expect(RefreshAdmission.forRecording(fetchedFrom: Self.server, as: Self.alice, keychainHolds: Self.alice, storeHolds: Self.server) == .admitted)
    }

    @Test
    func `A refresh overtaken by a sign-out writes nothing`() {
        // The sign-out deleted the account and cleared the Keychain, so neither holds anything any more; writing now
        // is what used to create a fresh account with no address and fill it with the old server's data.
        #expect(RefreshAdmission.forRecording(fetchedFrom: Self.server, as: Self.alice, keychainHolds: nil, storeHolds: nil) == .signedOut)
    }

    @Test(arguments: [
        Credentials(user: "alice", appPassword: "second-app-password"),
        Credentials(user: "bob", appPassword: "first-app-password"),
    ])
    func `A refresh overtaken by a sign-out and a sign-in to the same server writes nothing`(storedCredentials: Credentials) {
        // The address matches and the store has an account for it, which is exactly what would let the first
        // account's data into the second's: only the credentials tell them apart.
        #expect(RefreshAdmission.forRecording(fetchedFrom: Self.server, as: Self.alice, keychainHolds: storedCredentials, storeHolds: Self.server) == .signedInAgain)
    }

    @Test(arguments: [nil, URL(string: "https://other.example.com")!])
    func `A refresh whose credentials match writes nothing into a store holding another server, or none`(storedAddress: URL?) {
        #expect(RefreshAdmission.forRecording(fetchedFrom: Self.server, as: Self.alice, keychainHolds: Self.alice, storeHolds: storedAddress) == .storeHoldsAnotherAccount)
    }

    @Test
    func `A refresh made without credentials writes nothing`() {
        #expect(RefreshAdmission.forRecording(fetchedFrom: Self.server, as: nil, keychainHolds: Self.alice, storeHolds: Self.server) == .anonymous)
    }

    @Test
    func `Recording the address asks only the Keychain, the store being what it repairs`() {
        // A store with no address, beside a Keychain that still holds the account, is how an iOS install whose
        // credentials predate the store begins, and recording the address is how it is repaired.
        #expect(RefreshAdmission.forAdopting(fetchedAs: Self.alice, keychainHolds: Self.alice) == .admitted)
    }

    @Test
    func `Recording the address is refused once the account is signed out or signed in again`() {
        #expect(RefreshAdmission.forAdopting(fetchedAs: Self.alice, keychainHolds: nil) == .signedOut)
        #expect(RefreshAdmission.forAdopting(fetchedAs: Self.alice, keychainHolds: Credentials(user: "alice", appPassword: "second-app-password")) == .signedInAgain)
        #expect(RefreshAdmission.forAdopting(fetchedAs: nil, keychainHolds: Self.alice) == .anonymous)
    }
}
