// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV2_1 {
    /// `DevicePreferences` is the v2.1 record for the appearance choices made on the device, in the shape the live `DevicePreferences` has, so that the stage into `SchemaV3` can fill it before the account's copies of those choices are dropped.
    ///
    /// It is a frozen copy; see `SchemaV2_1` for why this intermediate schema exists and why it never changes.
    @Model
    final class DevicePreferences {
        /// `translucentAppearance` is the user's choice to let the macOS window material show through the web view; `nil` means the user has not chosen.
        var translucentAppearance: Bool?

        /// `removeGaps` is the user's choice to expand Nextcloud's content to the window edges; `nil` means the user has not chosen.
        var removeGaps: Bool?

        init(translucentAppearance: Bool? = nil, removeGaps: Bool? = nil) {
            self.translucentAppearance = translucentAppearance
            self.removeGaps = removeGaps
        }
    }
}
