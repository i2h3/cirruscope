// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `Account` is the SwiftData root record for the Nextcloud account the user has connected to: the server address, its cached branding and version, and the account-scoped domain records that belong to it.
///
/// It is the single anchor every other stored model relates back to, so future domain models — files, notes, Talk conversations, and so on — each gain an `account` relationship here and are partitioned per account for free. `AccountStore` maintains at most one `Account` today; the schema already supports several, so multi-account support later needs no migration.
///
/// `serverAddress` is optional because sign-in persists the server's theming and version (via `ServerConnection.validate(_:)`) before the validated address itself is stored: a freshly created `Account` therefore represents "connecting" until the address is filled in. Deleting the `Account` cascades to its `apps` (and, through them, their shortcuts), which is how `AccountStore.disconnect()` clears everything the account owns in one step.
///
/// Credentials are deliberately not stored here — secrets stay in `Keychain`, keyed by `serverAddress`, so the shared, unencrypted SwiftData store never holds them.
@Model
final class Account {
    /// `serverAddress` is the URL of the connected Nextcloud server, or `nil` while a sign-in is still in progress.
    var serverAddress: URL?

    /// `serverVersion` is the human-readable version string of the connected server, recorded by `ServerConnection.validate(_:)`.
    var serverVersion: String?

    /// `themeBackground` is the `background` value from the server's `Theming` capability: a URL string pointing to an image, or a hex color value.
    var themeBackground: String?

    /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability.
    var themeLogo: URL?

    /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability, indicating whether the background is a plain color rather than an image.
    var themeBackgroundPlain: Bool?

    /// `translucentAppearance` is the user's choice, from the Appearance settings tab, to let the macOS window material show through the web view instead of Nextcloud's own backgrounds; `nil` means the user has not chosen and the app default (off) applies.
    var translucentAppearance: Bool?

    /// `removeGaps` is the user's choice, from the Appearance settings tab, to expand Nextcloud's content to the window edges by removing the surrounding margins; `nil` means the user has not chosen and the app default (on) applies.
    var removeGaps: Bool?

    /// `apps` are the Nextcloud server apps offered by this account's server; deleting the account cascades to them and, through them, their shortcuts.
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
        themeBackgroundPlain: Bool? = nil,
        translucentAppearance: Bool? = nil,
        removeGaps: Bool? = nil
    ) {
        self.serverAddress = serverAddress
        self.serverVersion = serverVersion
        self.themeBackground = themeBackground
        self.themeLogo = themeLogo
        self.themeBackgroundPlain = themeBackgroundPlain
        self.translucentAppearance = translucentAppearance
        self.removeGaps = removeGaps
    }
}
