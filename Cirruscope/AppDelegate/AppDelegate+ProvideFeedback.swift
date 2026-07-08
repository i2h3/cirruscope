import Cocoa

/// `AppDelegate`'s feedback support opens the user's default mail app with a draft addressed to Cirruscope's feedback inbox, pre-filled with the environment details that help triage a report.
extension AppDelegate {
    /// `provideFeedback(_:)` opens the user's default mail app with a draft addressed to Cirruscope's feedback inbox.
    ///
    /// The body is pre-filled with the environment details that help triage a report — the macOS version, the app version, and, when a supported server is connected, the Nextcloud server version — so the user does not have to gather them by hand. It backs the Help-menu "Provide Feedback…" item, which targets the responder chain.
    @IBAction
    func provideFeedback(_: Any?) {
        let recipient = Settings.feedbackAddress
        let subject = "Cirruscope Feedback"

        guard let encodedRecipient = recipient.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = feedbackBody().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(encodedRecipient)?subject=\(encodedSubject)&body=\(encodedBody)")
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    /// `feedbackBody()` builds the pre-filled body of the feedback email.
    ///
    /// It leaves an empty area at the top for the user to write in, then lists the macOS and Cirruscope versions and appends the connected Nextcloud server version whenever `Settings.serverVersion` has one.
    private func feedbackBody() -> String {
        var details = [
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Cirruscope: \(appVersion)",
        ]

        if let serverVersion = Settings.serverVersion {
            details.append("Nextcloud server: \(serverVersion)")
        }

        return "\n\n\n— Please keep the lines below; they help us look into your feedback —\n" + details.joined(separator: "\n")
    }

    /// `appVersion` is Cirruscope's marketing version and build number read from the bundle, e.g. "1.0.0 (1)".
    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        return "\(shortVersion) (\(buildVersion))"
    }
}
