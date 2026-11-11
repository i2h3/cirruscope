// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `ServerAppsViewController` is the "Keyboard Shortcuts" tab of the settings window, listing the Nextcloud server apps and letting the user assign a keyboard shortcut to each.
class ServerAppsViewController: NSViewController {
    /// `tableView` lists the server apps, one row per `AccountStore.serverApps` entry, each with the app name and a shortcut recorder.
    @IBOutlet
    private var tableView: NSTableView!

    /// `apps` is the snapshot of `AccountStore.serverApps` that backs the table.
    private(set) var apps: [ServerAppTransferObject] = []

    /// `logger` records the Keyboard Shortcuts settings tab's activity under the `ServerAppsViewController` category.
    private let logger = Logger(for: ServerAppsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Keyboard Shortcuts settings tab loaded")

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
