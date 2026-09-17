// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension declares the in-process notifications `AccountStore` posts, which are shared because the store is.
///
/// They sit here rather than beside the rest of the app's notification names in `macOS/Settings/NotificationName.swift` for one reason: a name has to be visible where it is posted, and the store is compiled into both apps. What observes them is still platform code — the View and Dock menus and the Apps settings tab on macOS, the title menu on iOS — but what announces them is not, and a second declaration per platform would let the two drift on the string.
///
/// The file is named for the store rather than for the type it extends, which is not a stylistic choice: two files called `NotificationName.swift` in one target collide on the `.stringsdata` output Xcode derives from the base name, and the build fails with "Multiple commands produce". A synchronized folder makes that easy to walk into, since nothing about adding a file warns that another target already compiles one by that name.
extension Notification.Name {
    /// `serverAppsDidChange` is posted by `AccountStore` whenever the server apps or their shortcuts change, so every surface listing them rebuilds.
    static let serverAppsDidChange = Notification.Name("ServerAppsDidChange")

    /// `appearanceSettingsDidChange` is posted by `AccountStore` whenever the account's appearance settings (translucency, remove-gaps) change so every open web view re-applies them without a reload.
    static let appearanceSettingsDidChange = Notification.Name("AppearanceSettingsDidChange")
}
