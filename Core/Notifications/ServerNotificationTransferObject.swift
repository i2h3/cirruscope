// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerNotificationTransferObject` is the value snapshot of one notification the connected server still has queued for the user.
struct ServerNotificationTransferObject: Hashable, Identifiable, Sendable {
    /// `id` is the identifier the server gives the notification, unique for the user it is addressed to.
    let id: Int

    /// `app` is the identifier of the Nextcloud app that raised the notification, such as `spreed` for Talk.
    let app: String

    /// `creation` is when the server created the notification.
    let creation: Date

    /// `subject` is the notification's human-readable subject line, already in the user's language.
    let subject: String

    /// `message` is the notification's human-readable body, empty when it has none.
    let message: String

    /// `link` is the address the server names for opening the notification, exactly as it sent it, and empty when the notification cannot be opened through a link.
    let link: String
}
