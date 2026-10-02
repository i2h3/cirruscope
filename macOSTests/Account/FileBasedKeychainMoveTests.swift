// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Security
import Testing

///
/// `FileBasedKeychainMoveTests` pins `Keychain.moveFileBasedItems(service:)`, which carries the credentials releases up to `1.1.0` stored in macOS's file-based Keychain into the data-protection Keychain, and the three facts about those Keychains it rests on.
///
/// The facts are measured rather than assumed, because the move is only safe if they hold, and the first version of it rested on one that does not: that a query leaving `kSecUseDataProtectionKeychain` out addresses the file-based Keychain alone. In an entitled process it searches both, and a deletion made that way deletes from both, so deleting the file-based copy after making the new one deleted the new one too. Only setting the flag to `false` confines a query to the file-based Keychain. The first three cases ask the Keychain itself, so that belief cannot quietly come back.
/// Every case files its items under a service of its own (`KeychainScratchService`), never under `Keychain.service`, where the developer's real credentials are.
/// It is a macOS suite because only macOS has two Keychains to move between, and only the macOS app makes the move.
///
@Suite(.serialized)
struct FileBasedKeychainMoveTests {
    /// `scratch` is this case's own service in both Keychains, emptied again when the case ends.
    let scratch = KeychainScratchService()

    ///
    /// The fact the first version of the move got wrong, asserted so it stays written down: leaving the flag out reaches the data-protection Keychain too, for a read and for a deletion alike.
    ///
    @Test
    func `A query that leaves the flag out reaches the data-protection Keychain as well`() {
        #expect(scratch.add("data-protection", dataProtection: true) == errSecSuccess)

        #expect(scratch.unflaggedValue() == "data-protection")

        #expect(scratch.unflaggedDelete() == errSecSuccess)
        #expect(scratch.value(dataProtection: true) == nil)
    }

    ///
    /// With the flag set either way, an item in one Keychain is invisible from the other, which is what makes a move necessary at all, and what makes `Keychain.holdsFileBasedItems(service:)` a question about the file-based Keychain alone.
    ///
    @Test
    func `An item in either Keychain is invisible from the other`() {
        #expect(scratch.add("file-based", dataProtection: false) == errSecSuccess)
        #expect(scratch.value(dataProtection: true) == nil)
        #expect(Keychain.holdsFileBasedItems(service: scratch.service))

        scratch.delete(dataProtection: false)

        #expect(scratch.add("data-protection", dataProtection: true) == errSecSuccess)
        #expect(scratch.value(dataProtection: false) == nil)
        #expect(Keychain.holdsFileBasedItems(service: scratch.service) == false)
    }

    ///
    /// The move deletes the file-based copy with the flag set to `false`, right after making the new copy, so that deletion must leave the new copy alone.
    ///
    @Test
    func `Deleting from the file-based Keychain leaves the data-protection item in place`() {
        #expect(scratch.add("file-based", dataProtection: false) == errSecSuccess)
        #expect(scratch.add("data-protection", dataProtection: true) == errSecSuccess)

        #expect(scratch.delete(dataProtection: false) == errSecSuccess)

        #expect(scratch.value(dataProtection: false) == nil)
        #expect(scratch.value(dataProtection: true) == "data-protection")
    }

    ///
    /// The case every Mac updating from `1.1.0` is in: the credential is in the file-based Keychain only, and after the move it is in the data-protection Keychain only, unchanged.
    ///
    @Test
    func `A file-based credential moves into the data-protection Keychain`() {
        #expect(scratch.add("app password", dataProtection: false) == errSecSuccess)

        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 1)

        #expect(scratch.value(dataProtection: true) == "app password")
        #expect(scratch.value(dataProtection: false) == nil)
    }

    ///
    /// A credential already in the data-protection Keychain is the newer one — a sign-in after an earlier move wrote it — so it is kept, and the stale file-based copy goes rather than being moved over it.
    ///
    @Test
    func `A credential already in the data-protection Keychain is kept and the file-based copy removed`() {
        #expect(scratch.add("old app password", dataProtection: false) == errSecSuccess)
        #expect(scratch.add("new app password", dataProtection: true) == errSecSuccess)

        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 0)

        #expect(scratch.value(dataProtection: true) == "new app password")
        #expect(scratch.value(dataProtection: false) == nil)
    }

    ///
    /// A file-based item for another server, left behind by a sign-out whose deletion failed, must not be copied in beside the credential the data-protection Keychain already holds: two credentials would be two accounts, where everything that reads them takes the first in no defined order.
    ///
    @Test
    func `A leftover for another server is removed rather than copied beside the credential already there`() {
        #expect(scratch.add("leftover", dataProtection: false, account: "https://old.example.com") == errSecSuccess)
        #expect(scratch.add("current", dataProtection: true) == errSecSuccess)

        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 0)

        #expect(scratch.value(dataProtection: true, account: "https://old.example.com") == nil)
        #expect(scratch.value(dataProtection: false, account: "https://old.example.com") == nil)
        #expect(scratch.value(dataProtection: true) == "current")
    }

    ///
    /// A Mac that never ran a release storing credentials in the file-based Keychain has nothing to move, and the move must then touch nothing.
    ///
    @Test
    func `Nothing moves when the file-based Keychain holds nothing`() {
        #expect(scratch.add("app password", dataProtection: true) == errSecSuccess)

        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 0)

        #expect(scratch.value(dataProtection: true) == "app password")
    }

    ///
    /// A move that succeeded leaves nothing behind: a second launch finds nothing left to move.
    ///
    @Test
    func `A second move finds nothing left`() {
        #expect(scratch.add("app password", dataProtection: false) == errSecSuccess)

        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 1)
        #expect(Keychain.moveFileBasedItems(service: scratch.service) == 0)

        #expect(scratch.value(dataProtection: true) == "app password")
    }
}
