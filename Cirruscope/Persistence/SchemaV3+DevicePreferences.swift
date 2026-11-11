// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `DevicePreferences` is the v3 record for the appearance choices made on this device exactly as it shipped in `1.2.0` and `1.2.1`.
    @Model
    final class DevicePreferences {
        /// `translucentAppearance` is the user's choice, from the Appearance settings tab, to let the macOS window material show through the web view instead of Nextcloud's own backgrounds; `nil` means the user has not chosen and the app default (off) applies.
        var translucentAppearance: Bool?

        /// `removeGaps` is the user's choice, from the Appearance settings tab, to expand Nextcloud's content to the window edges by removing the surrounding margins; `nil` means the user has not chosen and the app default (on) applies.
        var removeGaps: Bool?

        init(translucentAppearance: Bool? = nil, removeGaps: Bool? = nil) {
            self.translucentAppearance = translucentAppearance
            self.removeGaps = removeGaps
        }
    }
}
