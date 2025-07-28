import os
import WebKit

///
/// Supported script message identifiers.
///
enum ScriptMessage: String, RawRepresentable {
    ///
    /// The injected user script finished its setup.
    ///
    case reportAvailability
}

///
/// Handles script messages sent from script code inside the web view.
/// 
class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ScriptMessageHandler")

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.debug("Did receive message: \(message)")

        guard message.name == "framecloud" else {
            logger.notice("Received script message with invalid message handler name \"\(message.name)\"!")
            return
        }

        guard let body = message.body as? [String: Any] else {
            logger.error("Failed to cast script message body as dictionary!")
            return
        }

        guard let rawMessageString = body.keys.first, let message = ScriptMessage(rawValue: rawMessageString) else {
            logger.error("Failed to acquire expected message identifier!")
            return
        }

        /*
        guard let arguments = body.values.first else {
            logger.error("Failed to acquire expected message arguments!")
            return
        }
        */

        switch message {
            case .reportAvailability:
                logger.debug("Availability reported.")
                break
        }
    }
}
