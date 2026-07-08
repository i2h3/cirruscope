import AuthenticationServices
import Cocoa

/// `ServerAddressViewController`'s conformance to `ASWebAuthenticationPresentationContextProviding` anchors the Login Flow v2 `ASWebAuthenticationSession` to this controller's window.
extension ServerAddressViewController: ASWebAuthenticationPresentationContextProviding {

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
