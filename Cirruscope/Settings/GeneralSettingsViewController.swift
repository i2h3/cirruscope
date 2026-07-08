import Cocoa
import os

class GeneralSettingsViewController: NSViewController {
    @IBOutlet var serverAddressButton: NSButton!

    /// `logger` records the general settings tab's activity under the `GeneralSettingsViewController` category.
    private let logger = Logger(for: GeneralSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("General settings tab loaded")

        serverAddressButton.title = Settings.serverAddress?.absoluteString ?? "Not set"
    }

    @IBAction func openServerAddress(_ sender: Any) {
        guard let url = Settings.serverAddress else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @IBAction func logOut(_ sender: Any) {
        logger.notice("Logging out; closing all windows and clearing the server address and credentials")

        for window in NSApplication.shared.windows {
            window.close()
        }

        Settings.serverAddress = nil

        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "ServerAddressWindowController") as? NSWindowController else {
            return
        }

        windowController.showWindow(self)
    }
}
