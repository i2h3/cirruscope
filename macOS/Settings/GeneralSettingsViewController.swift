// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `GeneralSettingsViewController` is the settings window's General tab: who the account signs in as, with its picture and name, the address of the connected server, which opens it in the browser, and the button that logs out.
class GeneralSettingsViewController: NSViewController {
    /// `avatar` shows the photograph the account uploaded to the server, cut to a circle, or a generic person symbol while there is none.
    @IBOutlet
    var avatar: NSImageView!

    /// `userName` shows the name the server displays for the account, the name it signs in with until the server has been asked, or nothing while nobody is signed in.
    @IBOutlet
    var userName: NSTextField!

    /// `serverAddressButton` shows the connected server's address, or that none is set, and opens that address when clicked.
    @IBOutlet
    var serverAddressButton: NSButton!

    /// `logger` records the general settings tab's activity under the `GeneralSettingsViewController` category.
    private let logger = Logger(for: GeneralSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("General settings tab loaded")

        // Decorative: the name beside it says whose picture it is.
        avatar.setAccessibilityElement(false)
        avatar.wantsLayer = true

        // A sign-out the app makes on its own leaves the settings window open, and so does signing in again
        // afterwards, so the account is shown again whenever the account store announces either: the account's
        // deletion, the app list the first refresh after a sign-in records, and who the account signs in as.
        NotificationCenter.default.addObserver(self, selector: #selector(accountDidChange), name: .serverAppsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accountDidChange), name: .currentUserDidChange, object: nil)
        showAccount()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        avatar.layer?.cornerRadius = avatar.bounds.height / 2
    }

    /// `accountDidChange()` shows the account again when the account store announces a change to it.
    @objc
    private func accountDidChange() {
        showAccount()
    }

    /// `showAccount()` shows who the account signs in as and titles `serverAddressButton` with the connected server's address, or says that none is set.
    private func showAccount() {
        let address = AccountStore.shared.serverAddress

        serverAddressButton.title = address?.absoluteString ?? String(localized: "Not set", comment: "Shown in the General settings tab in place of the server address while no server is connected.")
        userName.stringValue = AccountStore.shared.userDisplayName ?? address.flatMap { Keychain.credentials(for: $0)?.user } ?? ""

        if let photo = AccountStore.shared.userPhoto {
            avatar.image = NSImage(cgImage: photo, size: .zero)
            avatar.layer?.masksToBounds = true
        } else {
            avatar.image = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)
            avatar.layer?.masksToBounds = false
        }
    }

    @IBAction
    func openServerAddress(_: Any) {
        guard let url = AccountStore.shared.serverAddress else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @IBAction
    func logOut(_: Any) {
        (NSApp.delegate as? AppDelegate)?.logOut()
    }
}
