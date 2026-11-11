// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `AppDelegate`'s Spotlight continuation bridges a Spotlight result selection to the same opening logic the View and Dock menus, and the `Open…Intent` actions, use.
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
