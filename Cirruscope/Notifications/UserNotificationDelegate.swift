// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

/// `UserNotificationDelegate` is the delegate of `UNUserNotificationCenter` in both apps, deciding how a notification is presented while the app is in front and what a tap on one opens.
@MainActor
final class UserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// `logger` records what each tap came to under the `UserNotificationDelegate` category; it is `nonisolated` so the `nonisolated` callbacks can log through it.
    nonisolated let logger = Logger(for: UserNotificationDelegate.self)

    /// `presentationOptions` is how a notification arriving while the app is in front is presented.
    nonisolated let presentationOptions: UNNotificationPresentationOptions

    /// `willOpen` brings the app forward before a server notification is opened, where the app has to do that itself.
    private let willOpen: (@MainActor () -> Void)?

    /// `respondToOther` answers a tap on a notification that is not a server notification, with its request identifier and string `userInfo`.
    private let respondToOther: (@MainActor (String, [String: String]) -> Void)?

    /// `init(presentationOptions:willOpen:respondToOther:)` builds a delegate presenting with `presentationOptions`, calling `willOpen` before it opens a server notification and handing every other tap to `respondToOther`.
    init(presentationOptions: UNNotificationPresentationOptions, willOpen: (@MainActor () -> Void)? = nil, respondToOther: (@MainActor (String, [String: String]) -> Void)? = nil) {
        self.presentationOptions = presentationOptions
        self.willOpen = willOpen
        self.respondToOther = respondToOther
        super.init()
    }

    /// `configure()` makes this object the delegate of `UNUserNotificationCenter`.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        logger.notice("Installed the notification center delegate")
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(presentationOptions)
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = ServerNotificationContent.strings(from: response.notification.request.content.userInfo)

        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler()
            return
        }

        Task { @MainActor in
            self.respond(toNotificationWithIdentifier: identifier, userInfo: userInfo)
        }

        completionHandler()
    }

    /// `respond(toNotificationWithIdentifier:userInfo:)` opens what a tapped server notification names, or hands any other tapped notification to `respondToOther`.
    private func respond(toNotificationWithIdentifier identifier: String, userInfo: [String: String]) {
        guard let id = ServerNotificationContent.notificationID(fromIdentifier: identifier) else {
            guard let respondToOther else {
                logger.debug("A notification that is not a server notification was tapped, and nothing answers it")
                return
            }

            respondToOther(identifier, userInfo)
            return
        }

        willOpen?()

        let signedIn = (try? Keychain.storedAccounts())?.first

        switch ServerNotificationTap.resolve(identifier: identifier, userInfo: userInfo, signedIn: signedIn) {
            case let .open(target):
                logger.notice("Opening server notification \(id, privacy: .public)")
                EntityOpening.shared.open(.page(target))

            case .noLink:
                logger.notice("Server notification \(id, privacy: .public) has no address to open")

            case .otherAccount:
                logger.notice("Server notification \(id, privacy: .public) was posted for another account than the one signed in; opening nothing")

            case .notSignedIn:
                logger.notice("Server notification \(id, privacy: .public) was tapped while nobody is signed in; opening nothing")

            case .offOrigin:
                logger.error("Server notification \(id, privacy: .public) names an address off the signed-in server; opening nothing")

            case .notServerNotification:
                logger.debug("A tapped notification turned out not to be a server notification")
        }
    }
}
