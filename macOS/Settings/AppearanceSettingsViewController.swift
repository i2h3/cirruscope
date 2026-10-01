// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `AppearanceSettingsViewController` backs the Appearance tab of the settings window, whose two switches record how the web windows on this device draw Nextcloud: whether the window material shows through, and whether the gaps around Nextcloud's content are removed.
///
/// The choices are the device's rather than the account's: `AccountStore` keeps them apart from the connected account, so a sign-out leaves them in place and the next account signed in on this Mac opens with them.
/// Each switch writes as soon as it is flipped, and it is the store's `Notification.Name.appearanceSettingsDidChange` announcement, not this controller, that applies the change to every open web window without a reload.
class AppearanceSettingsViewController: NSViewController {
    /// `translucentAppearance` is the switch, labelled "Liquid Glass appearance" in the storyboard, that lets the macOS window material show through the web view instead of Nextcloud's own backgrounds.
    @IBOutlet
    var translucentAppearance: NSSwitch!

    /// `removeGaps` is the switch that expands Nextcloud's content to the window edges by removing the margins around it.
    @IBOutlet
    var removeGaps: NSSwitch!

    /// `logger` records the appearance settings tab's activity under the `AppearanceSettingsViewController` category.
    private let logger = Logger(for: AppearanceSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Appearance settings tab loaded")

        // Reflect the choices recorded on this device, applying the app defaults to any the user has not made yet: translucency is off by default, removing the content gaps is on.
        // The store answers `nil` for a choice never made and leaves the default to its callers, so these two must match the ones `WebViewController` applies.
        translucentAppearance.state = (AccountStore.shared.translucentAppearance ?? false) ? .on : .off
        removeGaps.state = (AccountStore.shared.removeGaps ?? true) ? .on : .off
    }

    /// `translucentAppearanceSwitched(_:)` records the translucency switch's new state as this device's choice through `AccountStore.setTranslucentAppearance(_:)`.
    @IBAction
    func translucentAppearanceSwitched(_: Any) {
        AccountStore.shared.setTranslucentAppearance(translucentAppearance.state == .on)
    }

    /// `gapsSwitched(_:)` records the remove-gaps switch's new state as this device's choice through `AccountStore.setRemoveGaps(_:)`.
    @IBAction
    func gapsSwitched(_: Any) {
        AccountStore.shared.setRemoveGaps(removeGaps.state == .on)
    }
}
