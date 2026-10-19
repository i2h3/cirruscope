// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation

///
/// `ServerNotificationFixture` is the accounts and notifications the server notification suites share, so they cannot drift apart on what an account or a notification looks like.
///
/// The accounts cover what tells two of them apart: another login name on the same server, the same login on another server, a new app password for the same login, and an instance installed in a subdirectory.
/// A notification is created at the reference date plus as many minutes as its identifier unless a case says otherwise, so the order of creation follows the identifiers by default and a case reversing it has to say so.
///
enum ServerNotificationFixture {
    ///
    /// `server` is the address of the server most cases talk to.
    ///
    static let server = URL(string: "https://cloud.example.com")!

    ///
    /// `alice` is the account most cases are signed in as.
    ///
    static let alice = ServerAccount(server: server, credentials: Credentials(user: "alice", appPassword: "alice-app-password"))

    ///
    /// `aliceNewPassword` is `alice` with a new app password for the same login, as a sign-in that replaces the credential without a sign-out leaves her.
    ///
    static let aliceNewPassword = ServerAccount(server: server, credentials: Credentials(user: "alice", appPassword: "alice-second-app-password"))

    ///
    /// `bob` is another login on the same server.
    ///
    static let bob = ServerAccount(server: server, credentials: Credentials(user: "bob", appPassword: "bob-app-password"))

    ///
    /// `otherServer` is the same login on another server.
    ///
    static let otherServer = ServerAccount(server: URL(string: "https://other.example.org")!, credentials: Credentials(user: "alice", appPassword: "alice-app-password"))

    ///
    /// `subdirectory` is an account on an instance installed under a path rather than at its host's root.
    ///
    static let subdirectory = ServerAccount(server: URL(string: "https://example.com/nextcloud")!, credentials: Credentials(user: "alice", appPassword: "alice-app-password"))

    ///
    /// `referenceDate` is the fixed moment notifications are created relative to.
    ///
    static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    ///
    /// `item(_:app:link:createdMinutesAfterReference:)` is the notification `id`, raised by `app`, opening `link`, created `minutes` after the reference date or `id` minutes after it when no minutes are given.
    ///
    static func item(_ id: Int, app: String = "spreed", link: String = "", createdMinutesAfterReference minutes: Int? = nil) -> ServerNotificationTransferObject {
        ServerNotificationTransferObject(id: id, app: app, creation: referenceDate.addingTimeInterval(TimeInterval((minutes ?? id) * 60)), subject: "Subject \(id)", message: "Message \(id)", link: link)
    }

    ///
    /// `items(_:)` is the notifications `ids`, in the order given, each with the defaults of `item(_:app:link:createdMinutesAfterReference:)`.
    ///
    static func items(_ ids: [Int]) -> [ServerNotificationTransferObject] {
        ids.map { item($0) }
    }

    ///
    /// `delivered(_:for:)` is the server notification `id` found in Notification Center, posted for `account`, or by a release that recorded no account when `account` is `nil`.
    ///
    static func delivered(_ id: Int, for account: ServerAccount?) -> ServerNotificationPlan.Delivered {
        ServerNotificationPlan.Delivered(id: id, recipient: account.map { ServerNotificationRecipient($0) })
    }

    ///
    /// `record(_:highWater:for:)` is a record of the identifiers `ids` with `highWater`, made for `account`.
    ///
    static func record(_ ids: Set<Int>, highWater: Int?, for account: ServerAccount) -> ServerNotificationRecord {
        ServerNotificationRecord(recipient: ServerNotificationRecipient(account), notificationIDs: ids, highWater: highWater)
    }
}
