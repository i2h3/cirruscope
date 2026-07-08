import AuthenticationServices
import Cocoa
import os
import Rainmaker

/// `ServerAddressViewController` backs the storyboard scene that asks the user for the address of the Nextcloud server they want to connect to.
///
/// It is presented by `AppDelegate` on launch when `Settings.serverAddress` is `nil`, validates the entered address by fetching the server's capabilities via `ServerConnection`, runs Nextcloud's Login Flow v2 in an `ASWebAuthenticationSession` to obtain an app password, and on success persists the address to `Settings.serverAddress` and the credentials to `Keychain` before handing off to `WebViewController`.
class ServerAddressViewController: NSViewController {

    /// `progressIndicator` is the indeterminate spinner that is animated while a server is being validated and the login is in progress.
    ///
    /// `open(_:)` shows and starts it before issuing the network request and hides and stops it once the flow has completed or failed.
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

    /// `authenticationSession` retains the `ASWebAuthenticationSession` that presents the Login Flow v2 grant page while polling is in progress.
    ///
    /// `startAuthenticationSession(using:)` assigns it, and `dismissAuthenticationSession()` cancels it once polling has produced credentials or stopped.
    private var authenticationSession: ASWebAuthenticationSession?

    /// `authenticationCancelled` is set by the `ASWebAuthenticationSession` completion handler when the user dismisses the grant sheet, signaling `pollForCredentials(on:flow:)` to stop.
    private var authenticationCancelled = false

    /// `logger` records the sign-in flow under the `ServerAddressViewController` category.
    private let logger = Logger(for: ServerAddressViewController.self)

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
            logger.error("Entered server address is not a valid URL")
            presentAlert(title: "Invalid Server Address", message: "“\(sanitizedServerAddress)” is not a valid URL. Please check the address and try again.")
            return
        }

        let server = ServerConnection.anonymous(address: url)

        serverAddressField.isEnabled = false
        openButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)

        Task {
            defer {
                serverAddressField.isEnabled = true
                openButton.isEnabled = true
                progressIndicator.isHidden = true
                progressIndicator.stopAnimation(self)
            }

            do {
                switch try await ServerConnection.validate(server) {
                    case let .unsupported(version):
                        logger.notice("Server version \(version) is unsupported")
                        presentAlert(title: "Unsupported Server Version", message: "Cirruscope requires Nextcloud server version \(Settings.minimumSupportedServerMajorVersion) or later. The server at “\(url.absoluteString)” is running version \(version).")

                    case .supported:
                        logger.info("Server supported; starting Login Flow v2")
                        let result = try await logIn(to: server)
                        try Keychain.store(Credentials(user: result.name, appPassword: result.password), for: result.server)
                        Settings.serverAddress = result.server
                        logger.info("Stored credentials and connected to \(result.server)")
                        (NSApp.delegate as? AppDelegate)?.presentWebViewWindow()
                        view.window?.close()

                        if let authenticated = ServerConnection.authenticated(address: result.server) {
                            await ServerConnection.refreshNavigationApps(using: authenticated)
                        }
                }
            } catch CirruscopeError.loginCancelled {
                logger.notice("Sign-in cancelled by the user")
            } catch {
                logger.error("Sign-in failed: \(error.localizedDescription)")
                presentAlert(title: "Could Not Reach Server", message: error.localizedDescription)
            }
        }
    }

    /// `logIn(to:)` runs Nextcloud's Login Flow v2 against `server`: it presents the grant page in an `ASWebAuthenticationSession` and concurrently polls the login endpoint until the user completes the grant.
    ///
    /// Login Flow v2 never invokes the session's `nc` callback URL, so a successful `server.poll(_:token:)` is what signals completion; the session is then dismissed by the `defer`. It throws `CirruscopeError.loginCancelled` if the user dismisses the sheet and `CirruscopeError.loginTimedOut` if the grant is not completed in time.
    private func logIn(to server: Server) async throws -> LoginResult {
        let flow = try await server.login()

        defer {
            dismissAuthenticationSession()
        }

        try startAuthenticationSession(using: flow.entry)

        return try await pollForCredentials(on: server, flow: flow)
    }

    /// `startAuthenticationSession(using:)` presents `url` in an `ASWebAuthenticationSession` so the user can authenticate and grant access.
    ///
    /// The session is retained in `authenticationSession`. Because Login Flow v2 never invokes the `nc` callback, the completion handler only fires when the user dismisses the sheet, which sets `authenticationCancelled` so `pollForCredentials(on:flow:)` stops. It throws `CirruscopeError.loginPresentationFailed` if the session cannot be presented.
    private func startAuthenticationSession(using url: URL) throws {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nc") { [weak self] _, _ in
            self?.logger.debug("Authentication sheet dismissed by the user")
            self?.authenticationCancelled = true
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true

        authenticationCancelled = false
        authenticationSession = session

        guard session.start() else {
            logger.error("Could not present the authentication session")
            throw CirruscopeError.loginPresentationFailed
        }
    }

    /// `pollForCredentials(on:flow:)` polls `server`'s login endpoint until the user completes the grant, returning the resulting credentials.
    ///
    /// While the grant is pending the endpoint yields no result and `server.poll(_:token:)` throws, so every failure is treated as "keep polling". It stops with `CirruscopeError.loginCancelled` if the user dismisses the sheet and `CirruscopeError.loginTimedOut` after a few minutes without completion.
    private func pollForCredentials(on server: Server, flow: LoginFlow) async throws -> LoginResult {
        let deadline = Date().addingTimeInterval(300)

        while Date() < deadline {
            try Task.checkCancellation()

            if authenticationCancelled {
                throw CirruscopeError.loginCancelled
            }

            if let result = try? await server.poll(flow.endpoint, token: flow.token) {
                logger.debug("Sign-in granted; received credentials")
                return result
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        logger.error("Sign-in timed out after 300 seconds")
        throw CirruscopeError.loginTimedOut
    }

    /// `dismissAuthenticationSession()` cancels and releases the `ASWebAuthenticationSession`, dismissing the grant sheet once the login has completed, failed, or been cancelled.
    private func dismissAuthenticationSession() {
        authenticationSession?.cancel()
        authenticationSession = nil
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

}
