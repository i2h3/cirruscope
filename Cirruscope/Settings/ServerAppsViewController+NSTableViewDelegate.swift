// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `ServerAppsViewController`'s conformance to `NSTableViewDelegate` builds each row's views: the app name in the first column and a `ShortcutRecorderView` bound to `Settings.appShortcuts` in the second.
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
