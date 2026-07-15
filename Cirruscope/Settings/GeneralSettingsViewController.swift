// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

class GeneralSettingsViewController: NSViewController {
    @IBOutlet
    var serverAddressButton: NSButton!

    /// `logger` records the general settings tab's activity under the `GeneralSettingsViewController` category.
    private let logger = Logger(for: GeneralSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("General settings tab loaded")

        serverAddressButton.title = Settings.serverAddress?.absoluteString ?? "Not set"
    }

    @IBAction
    func openServerAddress(_: Any) {
        guard let url = Settings.serverAddress else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @IBAction
    func logOut(_: Any) {
        (NSApp.delegate as? AppDelegate)?.logOut()
    }
}
