// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents

/// `ServerAppShortcuts` registers the App Shortcuts Cirruscope offers to Siri and the Shortcuts app, so the user can invoke them without assembling a shortcut by hand.
struct ServerAppShortcuts: AppShortcutsProvider {
    /// `appShortcuts` is the list of App Shortcuts the system registers for Cirruscope.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenServerAppIntent(),
            phrases: [
                "Open an app in \(.applicationName)",
                "Open \(.applicationName) \(\.$target)",
                "Open \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Nextcloud App",
            systemImageName: "cloud"
        )
    }
}
