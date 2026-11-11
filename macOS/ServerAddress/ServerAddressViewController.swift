// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AuthenticationServices
import Cocoa
import os
import Rainmaker
import WidgetKit

/// `ServerAddressViewController` backs the storyboard scene that asks the user for the address of the Nextcloud server they want to connect to.
class ServerAddressViewController: NSViewController {
    /// `progressIndicator` is the indeterminate spinner that is animated while a server is being validated and the login is in progress.
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// `serverAddressField` is the text field that captures the server address typed by the user.
    @IBOutlet
    var serverAddressField: NSTextField!

    /// `openButton` is the button that triggers `open(_:)` to validate the entered server address.
    @IBOutlet
    var openButton: NSButton!

    /// `schemeHintLabel` is the hint under `serverAddressField` that names the HTTPS default Cirruscope applied to an address the user entered without a scheme of its own.
    @IBOutlet
    var schemeHintLabel: NSTextField!

    /// `typedText` is the address as the user typed it, before `ServerAddressFormatter` rewrote the field to the canonical form.
    var typedText = ""

    /// `addressFormatter` rewrites `serverAddressField` to the canonical address whenever editing in it ends, so the address the app is about to request is the address the user can see.
    private let addressFormatter = ServerAddressFormatter()

    /// `logger` records the sign-in flow under the `ServerAddressViewController` category.
    private let logger = Logger(for: ServerAddressViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()

        serverAddressField.delegate = self
        serverAddressField.formatter = addressFormatter
    }

    /// `open(_:)` normalizes whatever is in `serverAddressField` through `ServerAddress`, shows the user the address it resolved to, and then validates that address against the server before running Login Flow v2.
    @IBAction
    func open(_: Any) {
        let address: ServerAddress

        do {
            // Read the field editor while there is one: clicking Connect without committing what was typed never ends
            // editing, because a push button does not accept first responder, so `ServerAddressFormatter` has not run.
            address = try ServerAddress(normalizing: serverAddressField.currentEditor()?.string ?? serverAddressField.stringValue)
        } catch {
            logger.error("Entered server address is not usable: \(String(describing: error))")
            presentAlert(title: String(localized: "Invalid Server Address", comment: "Alert title shown when the entered server address cannot be used to reach a Nextcloud server."), message: error.localizedDescription)
            return
        }

        // Show the resolved address before anything is requested, so a bare host name visibly becomes the `https://`
        // URL the request will use even on that path. Assigning `stringValue` also ends an editing session in
        // progress, and does so by aborting it, which sends neither a delegate message nor the field's action — so
        // nothing here can re-enter this method, and editing is provably over before the field is disabled below.
        serverAddressField.stringValue = address.displayString

        if address.inferredScheme {
            revealSchemeHint()
        }

        let server = ServerConnection.anonymous(address: address.url)

        serverAddressField.isEnabled = false
        openButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)

        Task {
            defer {
                serverAddressField.isEnabled = true
                updateOpenButtonEnablement()
                progressIndicator.isHidden = true
                progressIndicator.stopAnimation(self)
            }

            do {
                switch try await ServerConnection.validateAndPersist(server) {
                    case let .unsupported(capabilities):
                        let version = capabilities.version.string
                        logger.notice("Server version \(version) is unsupported")
                        presentAlert(title: String(localized: "Unsupported Server Version", comment: "Alert title shown when the server runs a Nextcloud version older than the app supports."), message: String(localized: "Cirruscope requires Nextcloud server version \(InfoPlist.minimumSupportedServerMajorVersion) or later. The server at “\(address.displayString)” is running version \(version).", comment: "Alert message shown when the server's Nextcloud version is too old; placeholders are the minimum supported major version, the server address, and the server's version."))

                    case .supported:
                        logger.info("Server supported; starting Login Flow v2")

                        // The Connect button that got here lives in this window, so it is on screen; a controller
                        // without one has nothing to anchor the grant sheet to and says so rather than presenting
                        // the sheet somewhere the user cannot see it.
                        guard let window = view.window else {
                            throw CirruscopeError.loginPresentationFailed
                        }

                        let result = try await LoginSession.signIn(to: server, anchoredTo: window)
                        let credentials = Credentials(user: result.name, appPassword: result.password)
                        try Keychain.store(credentials, for: result.server)
                        AccountStore.shared.connect(to: result.server)
                        logger.info("Stored credentials and connected to \(result.server)")

                        // The widget reads the credentials just stored, and would otherwise keep saying nobody is
                        // signed in until its next scheduled refresh.
                        WidgetCenter.shared.reloadAllTimelines()
                        (NSApp.delegate as? AppDelegate)?.presentWebViewWindow()
                        view.window?.close()

                        // Started here rather than left to the next launch, so the Dock badge and Notification Center
                        // follow the account from the moment it is signed in.
                        (NSApp.delegate as? AppDelegate)?.startNotificationMonitor(for: ServerAccount(server: result.server, credentials: credentials))

                        if let authenticated = ServerConnection.authenticated(address: result.server) {
                            await ServerConnection.refreshNavigationApps(using: authenticated)
                            await ServerConnection.refreshCurrentUser(using: authenticated)
                            await ServerConnection.refreshConversations(using: authenticated)
                            await ServerConnection.refreshNotes(using: authenticated)
                            await ServerConnection.refreshCollectives(using: authenticated)
                        }
                }
            } catch CirruscopeError.loginCancelled {
                logger.notice("Sign-in cancelled by the user")
            } catch {
                logger.error("Sign-in failed: \(error.localizedDescription)")
                presentAlert(title: String(localized: "Could Not Reach Server", comment: "Alert title shown when the server could not be reached during sign-in."), message: error.localizedDescription)
            }
        }
    }

    /// `updateOpenButtonEnablement()` keeps the Connect button enabled only while the address field holds something other than whitespace to submit.
    func updateOpenButtonEnablement() {
        let enteredText = serverAddressField.currentEditor()?.string ?? serverAddressField.stringValue

        openButton.isEnabled = enteredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// `revealSchemeHint()` shows the hint that HTTPS was assumed for an address entered without a scheme, and announces it once to assistive applications.
    func revealSchemeHint() {
        guard schemeHintLabel.isHidden else {
            return
        }

        logger.debug("Assumed HTTPS for an address entered without a scheme")

        schemeHintLabel.isHidden = false

        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: schemeHintLabel.stringValue, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// `presentAlert(title:message:)` reports a failure of the sign-in flow as a warning alert.
    ///
    /// It is presented as a sheet on the view's window where there is one — every caller runs while the Server Address window is on screen — and falls back to a modal alert otherwise, so a failure is never swallowed just because the window has already gone away.
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
}
