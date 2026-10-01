// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `RefreshAdmission` is whether what a refresh fetched may still be written to the store, and if not, why not.
///
/// A refresh fetches with a server whose credentials were captured when that server was built, and a sign-out does not stop one already under way: the app password is revoked on the server without waiting, so a fetch begun just before can still succeed just after.
/// Its results then belong to an account that is no longer signed in, and writing them would put the old server's apps, conversations, notes and collectives back into the store the sign-out just emptied — into a fresh account with no address, or into the account of whoever signed in next.
/// The question is therefore asked again at the moment of writing, of what the Keychain and the store hold then, rather than once when the refresh began.
///
/// The Keychain says whose credentials are signed in and the store which server, and both must still agree with the fetch: the Keychain's credentials must be the very ones it was made with, and the store must still record the server it asked, except when what is being recorded is that address itself.
/// A matching address is not enough: signing out and back in to the same server, possibly as somebody else, stores new credentials under the same address, and a refresh begun before would otherwise write the first account's data into the second's.
enum RefreshAdmission {
    /// `admitted` means the account the refresh fetched as is still the one signed in, so its results may be written.
    case admitted

    /// `anonymous` means the refresh fetched without credentials, so there is no account its results could belong to.
    case anonymous

    /// `signedOut` means the Keychain holds no credentials for the server fetched from any longer.
    case signedOut

    /// `signedInAgain` means the Keychain holds credentials for the server fetched from, but not the ones the refresh fetched with, which is a later sign-in, possibly as somebody else.
    case signedInAgain

    /// `storeHoldsAnotherAccount` means the credentials still match, but the store's account records another server, or none.
    case storeHoldsAnotherAccount

    /// `keychainUnreadable` means the Keychain refused to say what it holds, so whether the account is still signed in cannot be known.
    ///
    /// The pure decisions below never answer it; it is here so a caller that failed to read the Keychain can say so in the same terms, and a refresh then writes nothing, the store keeping what it had.
    case keychainUnreadable

    /// `forAdopting(fetchedAs:keychainHolds:)` is whether a refresh that fetched as `credentials` may record the address it fetched from, given the credentials the Keychain holds for that address now.
    ///
    /// The store is not consulted, because recording the address is how a store that lost or never learned it is repaired, so its own answer is the one thing that cannot be required to agree.
    static func forAdopting(fetchedAs credentials: Credentials?, keychainHolds storedCredentials: Credentials?) -> RefreshAdmission {
        guard let credentials else {
            return .anonymous
        }

        guard let storedCredentials else {
            return .signedOut
        }

        guard storedCredentials == credentials else {
            return .signedInAgain
        }

        return .admitted
    }

    /// `forRecording(fetchedFrom:as:keychainHolds:storeHolds:)` is whether a refresh that fetched from `address` as `credentials` may write what it fetched, given the credentials the Keychain holds for that address and the address the store's account records now.
    static func forRecording(fetchedFrom address: URL, as credentials: Credentials?, keychainHolds storedCredentials: Credentials?, storeHolds storedAddress: URL?) -> RefreshAdmission {
        let adoption = forAdopting(fetchedAs: credentials, keychainHolds: storedCredentials)

        guard case .admitted = adoption else {
            return adoption
        }

        guard storedAddress == address else {
            return .storeHoldsAnotherAccount
        }

        return .admitted
    }
}
