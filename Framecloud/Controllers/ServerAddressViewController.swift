import Cocoa
import Rainmaker

class ServerAddressViewController: NSViewController {
    @IBOutlet
    var progressIndicator: NSProgressIndicator!
    @IBOutlet
    var serverAddressField: NSTextField!
    @IBOutlet
    var openButton: NSButton!

    @IBAction
    func open(_: Any) {
        var sanitizedServerAddress = serverAddressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedServerAddress.hasPrefix("http://") == false || sanitizedServerAddress.hasPrefix("https://") == false {
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

                let minimumMajorVersion = Settings.minimumSupportedServerMajorVersion

                if capabilities.version.major >= minimumMajorVersion {
                    Settings.serverAddress = url
                    openWebViewWindow()
                    view.window?.close()
                } else {
                    presentAlert(title: "Unsupported Server", message: "Framecloud requires Nextcloud version \(minimumMajorVersion) or later. The server at “\(url.absoluteString)” is running version \(capabilities.version.string).")
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
