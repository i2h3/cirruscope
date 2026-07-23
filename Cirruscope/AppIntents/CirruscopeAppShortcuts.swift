// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents

/// `CirruscopeAppShortcuts` registers the App Shortcuts Cirruscope offers to Siri and the Shortcuts app, so the user can invoke them without assembling a shortcut by hand.
///
/// Its single entry binds `OpenServerAppIntent` to spoken phrases. Because the intent's `target` is a `ServerAppEntity` backed by an enumerable query, Siri and Shortcuts offer the connected server's apps as the parameter — so the parameterized phrases resolve as e.g. "Open Cirruscope Notes" or "Open Notes in Cirruscope". Every phrase must contain `\(.applicationName)`, which is why a bare "Open Nextcloud Notes" is expressed via Spotlight (see `ServerAppEntity.attributeSet`) rather than a phrase. `ServerAppIndexer` calls `updateAppShortcutParameters()` whenever the app list changes so the offered options stay current. After the `KeyboardShortcut` rename, `AppShortcut` here refers unambiguously to `AppIntents.AppShortcut`.
struct CirruscopeAppShortcuts: AppShortcutsProvider {
    /// `appShortcuts` is the list of App Shortcuts the system registers for Cirruscope.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenServerAppIntent(),
            phrases: [
                "Open \(.applicationName) \(\.$target)",
                "Open \(\.$target) in \(.applicationName)",
                "Open Nextcloud \(\.$target) in \(.applicationName)",
                "Open a Nextcloud app in \(.applicationName)",
            ],
            shortTitle: "Open Nextcloud App",
            systemImageName: "cloud"
        )
    }
}
