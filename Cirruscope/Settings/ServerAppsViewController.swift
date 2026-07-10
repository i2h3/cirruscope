// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `ServerAppsViewController` is the "Apps" tab of the settings window, listing the Nextcloud server apps and letting the user assign a keyboard shortcut to each.
///
/// It reads `Settings.serverApps` for the rows and writes `Settings.appShortcuts` as the user records shortcuts via the `ShortcutRecorderView` in each row, which prompts `AppDelegate` to rebuild the View and Dock menus.
/// The table's rows and views are supplied by `ServerAppsViewController+NSTableViewDataSource` and `ServerAppsViewController+NSTableViewDelegate`.
class ServerAppsViewController: NSViewController {
    /// `tableView` lists the server apps, one row per `Settings.serverApps` entry, each with the app name and a shortcut recorder.
    @IBOutlet
    private var tableView: NSTableView!

    /// `apps` is the snapshot of `Settings.serverApps` that backs the table.
    ///
    /// `reload()` refreshes it from `Settings`; the data source and delegate read it to populate the table, so it is settable only within this controller.
    private(set) var apps: [ServerApp] = []

    /// `logger` records the apps settings tab's activity under the `ServerAppsViewController` category.
    private let logger = Logger(for: ServerAppsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Apps settings tab loaded")

        reload()

        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
    }

    @objc
    private func serverAppsDidChange() {
        // Defer the reload so it does not rebuild the table from within a recorder's own event handling.
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }

    private func reload() {
        apps = Settings.serverApps
        tableView.reloadData()
    }
}
