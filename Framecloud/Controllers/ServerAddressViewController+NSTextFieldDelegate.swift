import Cocoa

/// `ServerAddressViewController`'s conformance to `NSTextFieldDelegate` keeps the "Open" button enabled only while the server-address field holds an address to submit.
extension ServerAddressViewController: NSTextFieldDelegate {

    func controlTextDidChange(_: Notification) {
        openButton.isEnabled = serverAddressField.stringValue.isEmpty == false
    }
}
