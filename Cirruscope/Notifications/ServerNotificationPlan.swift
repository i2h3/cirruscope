// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerNotificationPlan` is what one fetch of the server's notifications means for Notification Center and for the record of what was already seen: which notifications to post, which to withdraw, and what to remember next.
struct ServerNotificationPlan: Equatable, Sendable {
    /// `Delivered` is one server notification found in Notification Center, with the account it was posted for where it says.
    struct Delivered: Equatable, Sendable {
        /// `id` is the server's identifier of the notification.
        let id: Int

        /// `recipient` is the account it was posted for, or `nil` for one posted before notifications recorded it.
        let recipient: ServerNotificationRecipient?
    }

    /// `isBaseline` is whether this fetch was the first look at its account, so nothing was posted.
    let isBaseline: Bool

    /// `post` is the notifications to post, oldest first.
    let post: [ServerNotificationTransferObject]

    /// `withdraw` is the identifiers of the delivered notifications to remove from Notification Center.
    let withdraw: Set<Int>

    /// `record` is what to remember once this fetch has been acted on.
    let record: ServerNotificationRecord

    /// `make(listing:for:recorded:delivered:mayPost:)` decides what the fetch that answered `listing` for `recipient` means, given what was recorded before, what Notification Center holds, and whether posting is allowed at all just now.
    static func make(listing: [ServerNotificationTransferObject], for recipient: ServerNotificationRecipient, recorded: ServerNotificationRecord?, delivered: [Delivered], mayPost: Bool) -> ServerNotificationPlan {
        var listedIDs = Set<Int>()
        var unique: [ServerNotificationTransferObject] = []

        for item in listing where listedIDs.insert(item.id).inserted {
            unique.append(item)
        }

        let continuing = recorded?.recipient == recipient ? recorded : nil
        let highWater = [continuing?.highWater, listedIDs.max()].compactMap(\.self).max()
        let record = ServerNotificationRecord(recipient: recipient, notificationIDs: listedIDs, highWater: highWater)

        let withdraw = Set(delivered.filter { listedIDs.contains($0.id) == false || ($0.recipient != nil && $0.recipient != recipient) }.map(\.id))
        let kept = Set(delivered.map(\.id)).subtracting(withdraw)

        guard let continuing else {
            return ServerNotificationPlan(isBaseline: true, post: [], withdraw: withdraw, record: record)
        }

        guard mayPost else {
            return ServerNotificationPlan(isBaseline: false, post: [], withdraw: withdraw, record: record)
        }

        let floor = continuing.highWater

        let post = unique
            .filter { item in continuing.notificationIDs.contains(item.id) == false && kept.contains(item.id) == false && (floor.map { item.id > $0 } ?? true) }
            .sorted { ($0.creation, $0.id) < ($1.creation, $1.id) }

        return ServerNotificationPlan(isBaseline: false, post: post, withdraw: withdraw, record: record)
    }

    /// `withoutPosting()` is this plan with nothing to post, for a record that could not be written: posting what it would have recorded would post it again on every fetch.
    func withoutPosting() -> ServerNotificationPlan {
        ServerNotificationPlan(isBaseline: isBaseline, post: [], withdraw: withdraw, record: record)
    }
}
