// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `AppDelegate`'s Spotlight continuation bridges a Spotlight result selection to the same window logic the View and Dock menus, and `OpenServerAppIntent`, use.
///
/// When a user selects a `ServerAppEntity` that `ServerAppIndexer` donated to the Spotlight index, macOS foregrounds Cirruscope and delivers a `CSSearchableItemActionType` `NSUserActivity`. App Intents does not auto-run `OpenServerAppIntent` for that selection in an AppKit app, so this recovers the selected entity and opens it.
///
/// Reading the entity out of the activity is `SpotlightSelection`, shared with iOS, which receives the same activity through SwiftUI instead. What stays here is the part that is AppKit's: the `NSApplicationDelegate` continuation contract, and answering whether the activity was handled.
extension AppDelegate {
    /// `openServerAppFromSpotlight(_:)` opens the server app identified by a `CSSearchableItemActionType` activity, returning whether it handled the activity.
    func openServerAppFromSpotlight(_ userActivity: NSUserActivity) -> Bool {
        guard let app = SpotlightSelection.serverApp(from: userActivity) else {
            return false
        }

        logger.notice("Opening the Spotlight-selected server app \"\(app.id, privacy: .public)\"")
        openServerApp(app)
        return true
    }
}
