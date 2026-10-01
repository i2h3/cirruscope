// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `ServerAppsViewController` is the "Speed Dials" tab of the settings window, listing the Nextcloud server apps and letting the user assign a keyboard shortcut to each.
///
/// It reads `AccountStore.serverApps` for the rows and writes each app's shortcut via `AccountStore.setShortcut(_:forAppID:)` as the user records shortcuts through the `ShortcutRecorderView` in each row; the store announces that as `Notification.Name.keyboardShortcutsDidChange`, which prompts `AppDelegate` to rebuild the View menu and this tab to reload, while the Dock menu is built from the store each time it is opened and needs no prompting.
/// A shortcut belongs to this device and is keyed by the app's identifier, while only the apps the connected server offers have a row, so a shortcut recorded for an app it does not offer is neither shown nor editable here and applies again once a refresh lists that app.
/// The table's rows and views are supplied by `ServerAppsViewController+NSTableViewDataSource` and `ServerAppsViewController+NSTableViewDelegate`.
class ServerAppsViewController: NSViewController {
    /// `tableView` lists the server apps, one row per `AccountStore.serverApps` entry, each with the app name and a shortcut recorder.
    @IBOutlet
    private var tableView: NSTableView!

    /// `apps` is the snapshot of `AccountStore.serverApps` that backs the table.
    ///
    /// `reload()` refreshes it from `AccountStore`; the data source and delegate read it to populate the table, so it is settable only within this controller.
    private(set) var apps: [ServerAppTransferObject] = []

    /// `logger` records the Speed Dials settings tab's activity under the `ServerAppsViewController` category.
    private let logger = Logger(for: ServerAppsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Apps settings tab loaded")

        reload()

        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .keyboardShortcutsDidChange, object: nil)
    }

    /// `serverAppsDidChange()` reloads the table when the server apps or the keyboard shortcuts change.
    ///
    /// It observes the shortcuts as well as the apps because every row shows the shortcut that actually reaches its app, and one row's change can change another's: a shortcut stored for two apps is honoured for the first of them only, so clearing it from that one hands it to the next.
    @objc
    private func serverAppsDidChange() {
        // Defer the reload so it does not rebuild the table from within a recorder's own event handling.
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }

    private func reload() {
        apps = AccountStore.shared.serverApps
        tableView.reloadData()
    }
}
