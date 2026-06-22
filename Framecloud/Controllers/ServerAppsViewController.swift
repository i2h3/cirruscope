import Cocoa

/// `ServerAppsViewController` is the "Apps" tab of the settings window, listing the Nextcloud server apps and letting the user assign a keyboard shortcut to each.
///
/// It reads `Settings.serverApps` for the rows and writes `Settings.appShortcuts` as the user records shortcuts via the `ShortcutRecorderView` in each row, which prompts `AppDelegate` to rebuild the View and Dock menus.
class ServerAppsViewController: NSViewController {

    /// `tableView` lists the server apps, one row per `Settings.serverApps` entry, each with the app name and a shortcut recorder.
    @IBOutlet
    private var tableView: NSTableView!

    /// `apps` is the snapshot of `Settings.serverApps` that backs the table.
    private var apps: [ServerApp] = []

    override func viewDidLoad() {
        super.viewDidLoad()

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

extension ServerAppsViewController: NSTableViewDataSource {

    func numberOfRows(in _: NSTableView) -> Int {
        apps.count
    }
}

extension ServerAppsViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn)
        else {
            return nil
        }

        let app = apps[row]

        switch columnIndex {
            case 0:
                // The first column shows the app name in the storyboard's prototype cell view, falling
                // back to a plain label if no prototype is registered for the column.
                let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
                cell?.textField?.stringValue = app.name
                return cell ?? NSTextField(labelWithString: app.name)

            case 1:
                let recorder = ShortcutRecorderView(frame: .zero)
                recorder.shortcut = Settings.appShortcuts[app.id]

                recorder.onChange = { shortcut in
                    var shortcuts = Settings.appShortcuts
                    shortcuts[app.id] = shortcut
                    Settings.appShortcuts = shortcuts
                }
                
                return recorder

            default:
                return nil
        }
    }
}
