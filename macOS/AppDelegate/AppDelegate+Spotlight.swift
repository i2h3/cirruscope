// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `AppDelegate`'s Spotlight continuation bridges a Spotlight result selection to the same opening logic the View and Dock menus, and the `Open…Intent` actions, use.
///
/// When a user selects an entity that one of the indexers donated, macOS foregrounds Cirruscope and delivers a `CSSearchableItemActionType` `NSUserActivity`. App Intents does not auto-run the matching intent for that selection in an AppKit app, so this recovers what was selected and opens it.
///
/// Reading the selection is `SpotlightSelection`, shared with iOS, which receives the same activity through SwiftUI instead; serving it is `EntityOpening`, which this app installs its window logic into at launch. What stays here is the part that is AppKit's: the `NSApplicationDelegate` continuation contract, and answering whether the activity was handled.
extension AppDelegate {
    /// `openSpotlightSelection(_:)` opens whatever a `CSSearchableItemActionType` activity names, returning whether it handled the activity.
    func openSpotlightSelection(_ userActivity: NSUserActivity) -> Bool {
        guard let request = SpotlightSelection.request(from: userActivity) else {
            return false
        }

        logger.notice("Opening a Spotlight selection")
        EntityOpening.shared.open(request)
        return true
    }
}
