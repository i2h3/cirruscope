import Cocoa

class GeneralSettingsViewController: NSViewController {
    @IBOutlet var serverAddressButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        serverAddressButton.title = Settings.serverAddress?.absoluteString ?? "Not set"
    }

    @IBAction func openServerAddress(_ sender: Any) {
        guard let url = Settings.serverAddress else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @IBAction func logOut(_ sender: Any) {
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
