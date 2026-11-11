// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import UserNotifications

/// `ServerNotificationContent` is how a server notification is written into Notification Center and read back out of it: its request identifier, what its `userInfo` carries, and the request posting it.
enum ServerNotificationContent {
    /// `identifierPrefix` is what every server notification's request identifier starts with.
    static let identifierPrefix = "server-notification-"

    /// `linkKey` is the `userInfo` key of the absolute address a tap opens, present only when the notification has one on its own server.
    static let linkKey = "serverNotificationLink"

    /// `serverKey` is the `userInfo` key of the address of the server the notification was fetched from.
    static let serverKey = "serverNotificationServer"

    /// `loginNameKey` is the `userInfo` key of the login name of the account the notification was fetched as.
    static let loginNameKey = "serverNotificationLoginName"

    /// `identifier(for:)` is the request identifier of the server notification `id`.
    static func identifier(for id: Int) -> String {
        identifierPrefix + String(id)
    }

    /// `notificationID(fromIdentifier:)` is the server's identifier a request identifier was built from, or `nil` when it was not built by `identifier(for:)`.
    static func notificationID(fromIdentifier identifier: String) -> Int? {
        guard identifier.hasPrefix(identifierPrefix) else {
            return nil
        }

        guard let id = Int(identifier.dropFirst(identifierPrefix.count)) else {
            return nil
        }

        guard self.identifier(for: id) == identifier else {
            return nil
        }

        return id
    }

    /// `link(for:on:)` is the address a tap on `item` opens, or `nil` when it has none or the one it names leaves `server`.
    static func link(for item: ServerNotificationTransferObject, on server: URL) -> SameOriginURL? {
        guard item.link.isEmpty == false else {
            return nil
        }

        return SameOriginURL(path: item.link, relativeTo: server)
    }

    /// `userInfo(for:to:)` is what the notification posted for `item` carries: the account it was fetched as and, where it has one on that server, the address a tap opens.
    static func userInfo(for item: ServerNotificationTransferObject, to recipient: ServerNotificationRecipient) -> [String: String] {
        var userInfo = [
            serverKey: recipient.server.absoluteString,
            loginNameKey: recipient.loginName,
        ]

        if let link = link(for: item, on: recipient.server) {
            userInfo[linkKey] = link.url.absoluteString
        }

        return userInfo
    }

    /// `request(for:to:)` is the request that posts `item`, fetched as `recipient`, to Notification Center.
    ///
    /// The title and the body are the server's own subject and message, already in the user's language, and the thread is the Nextcloud app that raised the notification, so Notification Center groups them by app.
    /// No sound is set, as none ever was on the Mac.
    static func request(for item: ServerNotificationTransferObject, to recipient: ServerNotificationRecipient) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.subject
        content.body = item.message
        content.threadIdentifier = item.app
        content.userInfo = userInfo(for: item, to: recipient)

        return UNNotificationRequest(identifier: identifier(for: item.id), content: content, trigger: nil)
    }

    /// `recipient(from:)` is the account a delivered notification says it was posted for, or `nil` when it does not say, as one posted by a release before 1.3.0 does not.
    static func recipient(from userInfo: [String: String]) -> ServerNotificationRecipient? {
        guard let serverString = userInfo[serverKey] else {
            return nil
        }

        guard let server = URL(string: serverString) else {
            return nil
        }

        guard let loginName = userInfo[loginNameKey] else {
            return nil
        }

        return ServerNotificationRecipient(server: server, loginName: loginName)
    }

    /// `delivered(identifier:userInfo:)` is the server notification a delivered request stands for, or `nil` when it is not one, such as a web page's or a finished download's.
    static func delivered(identifier: String, userInfo: [String: String]) -> ServerNotificationPlan.Delivered? {
        guard let id = notificationID(fromIdentifier: identifier) else {
            return nil
        }

        return ServerNotificationPlan.Delivered(id: id, recipient: recipient(from: userInfo))
    }

    /// `strings(from:)` is the string-valued entries of a delivered notification's `userInfo`, which are all a server notification carries, as a dictionary that can cross an isolation boundary.
    static func strings(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var strings: [String: String] = [:]

        for (key, value) in userInfo {
            guard let key = key as? String else {
                continue
            }

            guard let value = value as? String else {
                continue
            }

            strings[key] = value
        }

        return strings
    }
}
