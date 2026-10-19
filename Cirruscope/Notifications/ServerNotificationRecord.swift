// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `ServerNotificationRecord` is what the app remembers about the server's notifications between fetches: whose they were, which ones the last fetch listed, and the highest identifier it has ever seen for that account.
///
/// It is the whole of what decides that a notification is new, and it holds numbers only, never a subject, a message or a link.
/// The listing is replaced by every fetch rather than added to, so it stays as small as the server's own list and needs no pruning.
/// The highest identifier survives a fetch that lists nothing, which is what keeps notifications the server lists again after an empty answer from being taken for new ones.
/// It lives in `Cirruscope/` because the widget extension has no use for it.
///
struct ServerNotificationRecord: Codable, Equatable, Sendable {
    ///
    /// `recipient` is the account the record was made for; a record made for anybody else is ignored.
    ///
    let recipient: ServerNotificationRecipient

    ///
    /// `notificationIDs` is the identifiers the last fetch admitted for `recipient` listed.
    ///
    let notificationIDs: Set<Int>

    ///
    /// `highWater` is the highest identifier ever recorded for `recipient`, or `nil` while none has been.
    ///
    let highWater: Int?
}
