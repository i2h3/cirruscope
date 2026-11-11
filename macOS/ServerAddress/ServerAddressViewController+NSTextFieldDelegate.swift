// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `ServerAddressViewController`'s conformance to `NSTextFieldDelegate` keeps the "Connect" button enabled only while the server-address field holds an address to submit, and names the address `ServerAddressFormatter` resolved once the user has finished entering one.
extension ServerAddressViewController: NSTextFieldDelegate {
    func controlTextDidChange(_: Notification) {
        // Keep the raw input around: once editing ends, `ServerAddressFormatter` replaces the field's value with the
        // canonical address, and from then on the field can no longer tell whether the user typed a scheme themselves
        // — which is exactly what decides whether the HTTPS hint has anything to explain.
        typedText = serverAddressField.currentEditor()?.string ?? serverAddressField.stringValue

        updateOpenButtonEnablement()

        // Any edit retires the hint: it describes an address the user has just moved on from.
        schemeHintLabel.isHidden = true
    }

    func controlTextDidEndEditing(_: Notification) {
        if (try? ServerAddress(normalizing: typedText))?.inferredScheme == true {
            revealSchemeHint()
        }
    }
}
