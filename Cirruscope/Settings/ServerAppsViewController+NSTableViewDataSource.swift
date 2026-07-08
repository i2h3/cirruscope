import Cocoa

/// `ServerAppsViewController`'s conformance to `NSTableViewDataSource` reports one row per `Settings.serverApps` entry held in its `apps` snapshot.
extension ServerAppsViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        apps.count
    }
}
