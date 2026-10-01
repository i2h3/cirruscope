// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `Account` is the SwiftData root record for the Nextcloud account the user has connected to: the server address, its cached branding and version, and the account-scoped domain records that belong to it.
///
/// It is the anchor every record describing the server relates back to, directly or through a parent: the server apps, Talk conversations, notes and collectives each have an `account` relationship here, a collective's pages hang off it, and a later domain model gains a relationship here the same way, so each is partitioned per account for free. `AccountStore` maintains at most one `Account` today; the schema already supports several, so multi-account support later needs no migration.
///
/// What the user sets up on this device is deliberately not here: the keyboard shortcuts and the appearance settings are records of their own, `KeyboardShortcut` and `DevicePreferences`, with no relationship to an account, so deleting the account at a sign-out leaves them in place.
///
/// `serverAddress` is optional because the Mac's sign-in persists the server's theming and version (via `ServerConnection.validateAndPersist(_:)`) before the validated address itself is stored: a freshly created `Account` therefore represents "connecting" until the address is filled in. Deleting the `Account` cascades to its apps, conversations, collectives and notes, and through them to the collectives' pages, which is how `AccountStore.disconnect()` clears everything the server sent in one step.
///
/// Credentials are deliberately not stored here — secrets stay in `Keychain`, keyed by `serverAddress`, so the shared, unencrypted SwiftData store never holds them.
@Model
final class Account {
    /// `serverAddress` is the URL of the connected Nextcloud server, or `nil` while a sign-in is still in progress.
    var serverAddress: URL?

    /// `serverVersion` is the human-readable version string of the connected server, recorded by `ServerConnection.validateAndPersist(_:)`, which only macOS calls.
    var serverVersion: String?

    /// `themeBackground` is the `background` value from the server's `Theming` capability: a URL string pointing to an image, or a hex color value.
    var themeBackground: String?

    /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability.
    var themeLogo: URL?

    /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability, indicating whether the background is a plain color rather than an image.
    var themeBackgroundPlain: Bool?

    /// `apps` are the Nextcloud server apps offered by this account's server; deleting the account cascades to them.
    @Relationship(deleteRule: .cascade, inverse: \ServerApp.account)
    var apps: [ServerApp] = []

    /// `conversations` are the Nextcloud Talk conversations this account takes part in; deleting the account cascades to them.
    ///
    /// Cascading is what makes signing out a single step rather than a list of things to remember. A conversation's display name is the name of a person in a one-to-one conversation, so leaving these behind would mean an unencrypted file naming people the account is no longer allowed to see.
    @Relationship(deleteRule: .cascade, inverse: \TalkConversation.account)
    var conversations: [TalkConversation] = []

    /// `collectives` are the collectives this account is a member of; deleting the account cascades to them, and through them to their pages.
    ///
    /// Two levels of cascade rather than one, because a page belongs to a collective rather than to the account: that is the shape of the address as well as of the data, a page being reachable only through the collective containing it.
    @Relationship(deleteRule: .cascade, inverse: \ServerCollective.account)
    var collectives: [ServerCollective] = []

    /// `notes` are the notes in this account's Nextcloud Notes app; deleting the account cascades to them.
    ///
    /// Only their titles and categories, never their text — see `ServerNote`. Cascading matters here for the same reason it does for the conversations: a note's title is something the user wrote, and it must not outlive the account that was allowed to read it.
    @Relationship(deleteRule: .cascade, inverse: \ServerNote.account)
    var notes: [ServerNote] = []

    init(
        serverAddress: URL? = nil,
        serverVersion: String? = nil,
        themeBackground: String? = nil,
        themeLogo: URL? = nil,
        themeBackgroundPlain: Bool? = nil
    ) {
        self.serverAddress = serverAddress
        self.serverVersion = serverVersion
        self.themeBackground = themeBackground
        self.themeLogo = themeLogo
        self.themeBackgroundPlain = themeBackgroundPlain
    }
}
