// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerNotificationTap` decides what a tap on a server notification in Notification Center opens, if anything.
enum ServerNotificationTap {
    /// `Resolution` is what one tap comes to.
    enum Resolution: Sendable {
        /// `open` carries the address to open, proven to stay on the signed-in server.
        case open(SameOriginURL)

        /// `noLink` means the notification has no address to open, which is an ordinary notification rather than a refusal.
        case noLink

        /// `otherAccount` means the notification was posted for another account than the one signed in.
        case otherAccount

        /// `notSignedIn` means nobody is signed in, so there is nowhere to open anything.
        case notSignedIn

        /// `offOrigin` means the address the notification carries leaves the signed-in server.
        case offOrigin

        /// `notServerNotification` means the tapped notification is not a server notification at all.
        case notServerNotification
    }

    /// `resolve(identifier:userInfo:signedIn:)` decides what the tap on the notification with `identifier` and `userInfo` opens while `signedIn` is the account signed in.
    ///
    /// A notification that does not say whom it was posted for, as one delivered by a release before 1.3.0 does not, is taken to belong to whoever is signed in, its address still having to stay on that account's server.
    static func resolve(identifier: String, userInfo: [String: String], signedIn: ServerAccount?) -> Resolution {
        guard ServerNotificationContent.notificationID(fromIdentifier: identifier) != nil else {
            return .notServerNotification
        }

        guard let signedIn else {
            return .notSignedIn
        }

        if let recipient = ServerNotificationContent.recipient(from: userInfo), recipient != ServerNotificationRecipient(signedIn) {
            return .otherAccount
        }

        guard let link = userInfo[ServerNotificationContent.linkKey], link.isEmpty == false else {
            return .noLink
        }

        guard let target = SameOriginURL(path: link, relativeTo: signedIn.server) else {
            return .offOrigin
        }

        return .open(target)
    }
}
