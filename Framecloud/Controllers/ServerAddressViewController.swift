import Cocoa
import Rainmaker

/// `ServerAddressViewController` backs the storyboard scene that asks the user for the address of the Nextcloud server they want to connect to.
///
/// It is presented by `AppDelegate` on launch when `Settings.serverAddress` is `nil`, validates the entered address by fetching the server's capabilities via `Rainmaker.Server`, and on success persists the address to `Settings.serverAddress` before handing off to `WebViewController`.
class ServerAddressViewController: NSViewController {

    /// `progressIndicator` is the indeterminate spinner that is animated while a server's capabilities are being fetched.
    ///
    /// `open(_:)` shows and starts it before issuing the network request and hides and stops it once the request has completed or failed.
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// `serverAddressField` is the text field that captures the server address typed by the user.
    ///
    /// `open(_:)` reads its `stringValue`, sanitizes it, and disables the field while validating the resulting URL against the server.
    @IBOutlet
    var serverAddressField: NSTextField!

    /// `openButton` is the button that triggers `open(_:)` to validate the entered server address.
    ///
    /// `open(_:)` disables it while a validation request is in flight to prevent duplicate submissions.
    @IBOutlet
    var openButton: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        serverAddressField.delegate = self
    }

    @IBAction
    func open(_: Any) {
        var sanitizedServerAddress = serverAddressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedServerAddress.hasPrefix("http://") == false && sanitizedServerAddress.hasPrefix("https://") == false {
            sanitizedServerAddress = "https://".appending(sanitizedServerAddress)
        }

        if sanitizedServerAddress.hasSuffix("/") == false {
            sanitizedServerAddress.append("/")
        }

        guard let url = URL(string: sanitizedServerAddress) else {
            presentAlert(title: "Invalid Server Address", message: "“\(sanitizedServerAddress)” is not a valid URL. Please check the address and try again.")
            return
        }

        let server = Server(address: url)

        serverAddressField.isEnabled = false
        openButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)

        Task {
            do {
                let capabilities = try await server.capabilities()

                if let theming = try? capabilities.get(Theming.self) {
                    await Settings.persist(theming: theming)
                }

                let minimumMajorVersion = Settings.minimumSupportedServerMajorVersion

                if capabilities.version.major >= minimumMajorVersion {
                    Settings.serverAddress = url
                    openWebViewWindow()
                    view.window?.close()
                } else {
                    presentAlert(title: "Unsupported Server Version", message: "Framecloud requires Nextcloud server version \(minimumMajorVersion) or later. The server at “\(url.absoluteString)” is running version \(capabilities.version.string).")
                }
            } catch {
                presentAlert(title: "Could Not Reach Server", message: error.localizedDescription)
            }

            serverAddressField.isEnabled = true
            openButton.isEnabled = true
            progressIndicator.isHidden = true
            progressIndicator.stopAnimation(self)
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func openWebViewWindow() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? NSWindowController else {
            return
        }

        windowController.showWindow(self)
    }
}
extension ServerAddressViewController: NSTextFieldDelegate {
    func controlTextDidChange(_: Notification) {
        openButton.isEnabled = serverAddressField.stringValue.isEmpty == false
    }
}

