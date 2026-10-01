// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `GeneralSettingsViewController` is the settings window's General tab: the address of the connected server, which opens it in the browser, and the button that logs out.
class GeneralSettingsViewController: NSViewController {
    /// `serverAddressButton` shows the connected server's address, or that none is set, and opens that address when clicked.
    @IBOutlet
    var serverAddressButton: NSButton!

    /// `logger` records the general settings tab's activity under the `GeneralSettingsViewController` category.
    private let logger = Logger(for: GeneralSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("General settings tab loaded")

        // Logging out from this tab leaves the settings window open, and so does signing in again afterwards, so the
        // address is shown again whenever the account store announces either: the account's deletion, and the app
        // list the first refresh after a sign-in records.
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        showServerAddress()
    }

    /// `serverAppsDidChange()` shows the server address again when the account store announces a change to the account.
    @objc
    private func serverAppsDidChange() {
        showServerAddress()
    }

    /// `showServerAddress()` titles `serverAddressButton` with the connected server's address, or says that none is set.
    private func showServerAddress() {
        serverAddressButton.title = AccountStore.shared.serverAddress?.absoluteString ?? String(localized: "Not set", comment: "Shown in the General settings tab in place of the server address while no server is connected.")
    }

    @IBAction
    func openServerAddress(_: Any) {
        guard let url = AccountStore.shared.serverAddress else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @IBAction
    func logOut(_: Any) {
        (NSApp.delegate as? AppDelegate)?.logOut()
    }
}
