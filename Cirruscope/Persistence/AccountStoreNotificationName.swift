// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension declares the in-process notifications the shared layer posts, which are shared because the store is. `AccountStore` posts every one of them, and `ServerConnection` posts four of them again once pictures it fetched have landed: `serverAppsDidChange` and `donatedArtworkDidChange` after the app icons, `conversationsDidChange` after the conversations' pictures, and `currentUserDidChange` after the account's own. All eight are declared here because a name belongs in one place rather than beside whichever type happens to post it.
extension Notification.Name {
    /// `serverAppsDidChange` is posted by `AccountStore` whenever the server apps change or the account's recorded server address is corrected, and by `ServerConnection` once the apps' icons have landed, so every surface listing them rebuilds.
    static let serverAppsDidChange = Notification.Name("ServerAppsDidChange")

    /// `keyboardShortcutsDidChange` is posted by `AccountStore` whenever a keyboard shortcut is recorded, replaced or cleared, so the View menu and the Keyboard Shortcuts tab redraw; the Dock menu reads the store afresh each time it opens and needs no prompting.
    static let keyboardShortcutsDidChange = Notification.Name("KeyboardShortcutsDidChange")

    /// `appearanceSettingsDidChange` is posted by `AccountStore` whenever the device's appearance settings (translucency, remove-gaps) change so every open web view re-applies them without a reload.
    static let appearanceSettingsDidChange = Notification.Name("AppearanceSettingsDidChange")

    /// `conversationsDidChange` is posted by `AccountStore` whenever the account's Talk conversations change, and by `ServerConnection` once their pictures have landed, so the Spotlight index is brought back into step with them.
    ///
    /// A name of its own rather than one announcement for every domain, because the surfaces are not the same: a change to the conversations has nothing to say to the View menu or the Keyboard Shortcuts settings tab, and waking every one of them for it would make each domain's refresh cost grow with the number of domains there are.
    static let conversationsDidChange = Notification.Name("ConversationsDidChange")

    /// `notesDidChange` is posted by `AccountStore` whenever the account's notes change, so the Spotlight index is brought back into step with them.
    static let notesDidChange = Notification.Name("NotesDidChange")

    /// `collectivesDidChange` is posted by `AccountStore` whenever the account's collectives or their pages change, so the Spotlight index is brought back into step with them.
    ///
    /// One name for both, where every other domain has its own, because a page is only ever reached through its collective: nothing observes one without observing the other, and two names would mean two reindex passes for one refresh.
    static let collectivesDidChange = Notification.Name("CollectivesDidChange")

    /// `donatedArtworkDidChange` is posted whenever something the Spotlight artwork is drawn from lands, so every index that draws one is donated again with the picture in it.
    static let donatedArtworkDidChange = Notification.Name("DonatedArtworkDidChange")

    /// `currentUserDidChange` is posted by `AccountStore` whenever who the account signs in as is recorded or deleted, and by `ServerConnection` once the account's own picture has landed, so the surfaces showing the account's name and picture redraw.
    static let currentUserDidChange = Notification.Name("CurrentUserDidChange")
}
