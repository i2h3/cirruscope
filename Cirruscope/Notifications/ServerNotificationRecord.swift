// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerNotificationRecord` is what the app remembers about the server's notifications between fetches: whose they were, which ones the last fetch listed, and the highest identifier it has ever seen for that account.
struct ServerNotificationRecord: Codable, Equatable, Sendable {
    /// `recipient` is the account the record was made for; a record made for anybody else is ignored.
    let recipient: ServerNotificationRecipient

    /// `notificationIDs` is the identifiers the last fetch admitted for `recipient` listed.
    let notificationIDs: Set<Int>

    /// `highWater` is the highest identifier ever recorded for `recipient`, or `nil` while none has been.
    let highWater: Int?
}
