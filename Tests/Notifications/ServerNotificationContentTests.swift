// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing
import UserNotifications

/// `ServerNotificationContentTests` covers how a server notification is written into Notification Center and read back out of it.
struct ServerNotificationContentTests {
    // MARK: - Identifiers

    @Test(arguments: [0, 1, 42, Int.max])
    func `An identifier reads back as the notification it was built for`(id: Int) {
        #expect(ServerNotificationContent.notificationID(fromIdentifier: ServerNotificationContent.identifier(for: id)) == id)
    }

    @Test
    func `The identifier is the one releases before this one wrote`() {
        // A notification the Mac delivered before notifications recorded their account is recognized only because
        // the spelling never changed.
        #expect(ServerNotificationContent.identifier(for: 42) == "server-notification-42")
    }

    @Test(arguments: ["0D9F1E2C-3B4A-4C5D-8E6F-7A8B9C0D1E2F", "web-notification-server-notification-5", "server-notification-", "server-notification-abc", "server-notification-+5", "server-notification-05", "server-notification- 5", "Server-Notification-5"])
    func `An identifier not spelled exactly as built is nobody's notification`(identifier: String) {
        #expect(ServerNotificationContent.notificationID(fromIdentifier: identifier) == nil)
    }

    // MARK: - Requests

    @Test
    func `A request carries the subject, the message and the app it groups under, and no sound`() {
        let item = ServerNotificationFixture.item(7, app: "files_sharing")
        let request = ServerNotificationContent.request(for: item, to: ServerNotificationRecipient(ServerNotificationFixture.alice))

        #expect(request.identifier == "server-notification-7")
        #expect(request.content.title == "Subject 7")
        #expect(request.content.body == "Message 7")
        #expect(request.content.threadIdentifier == "files_sharing")
        #expect(request.content.sound == nil)
        #expect(request.trigger == nil)
    }

    @Test
    func `A request carries strings only, and never the app password`() {
        let item = ServerNotificationFixture.item(7, link: "/apps/spreed/call/abc")
        let request = ServerNotificationContent.request(for: item, to: ServerNotificationRecipient(ServerNotificationFixture.alice))

        for value in request.content.userInfo.values {
            #expect(value is String)
            #expect((value as? String)?.contains(ServerNotificationFixture.alice.credentials.appPassword) == false)
        }
    }

    // MARK: - Links

    @Test(arguments: [
        (ServerNotificationFixture.alice, "/apps/spreed/call/abc", "https://cloud.example.com/apps/spreed/call/abc"),
        (ServerNotificationFixture.alice, "https://cloud.example.com/apps/files/?fileid=3", "https://cloud.example.com/apps/files/?fileid=3"),
        (ServerNotificationFixture.subdirectory, "/nextcloud/apps/files/", "https://example.com/nextcloud/apps/files/"),
    ])
    func `A link on the notification's own server is kept as an absolute address`(account: ServerAccount, link: String, expected: String) {
        let userInfo = ServerNotificationContent.userInfo(for: ServerNotificationFixture.item(1, link: link), to: ServerNotificationRecipient(account))

        #expect(userInfo[ServerNotificationContent.linkKey] == expected)
    }

    @Test(arguments: ["", "https://evil.example/x", "//evil.example/x", "http://cloud.example.com/apps/files/"])
    func `A link that is missing or leaves the server is not carried`(link: String) {
        let userInfo = ServerNotificationContent.userInfo(for: ServerNotificationFixture.item(1, link: link), to: ServerNotificationRecipient(ServerNotificationFixture.alice))

        #expect(userInfo[ServerNotificationContent.linkKey] == nil)
        #expect(userInfo[ServerNotificationContent.serverKey] == "https://cloud.example.com")
        #expect(userInfo[ServerNotificationContent.loginNameKey] == "alice")
    }

    // MARK: - Reading back

    @Test(arguments: ["https://cloud.example.com", "https://cloud.example.com/", "https://example.com/nextcloud", "https://cloud.example.com:8443"])
    func `The account a notification was posted for survives Notification Center`(server: String) throws {
        // Measures `UNMutableNotificationContent` rather than assuming it: what is read back is the `userInfo` the
        // framework hands over, and a recipient that came back unequal would withdraw every notification as another
        // account's.
        let recipient = try ServerNotificationRecipient(server: #require(URL(string: server)), loginName: "alice@example.com")
        let request = ServerNotificationContent.request(for: ServerNotificationFixture.item(3), to: recipient)
        let userInfo = ServerNotificationContent.strings(from: request.content.userInfo)

        #expect(ServerNotificationContent.recipient(from: userInfo) == recipient)
        #expect(ServerNotificationContent.delivered(identifier: request.identifier, userInfo: userInfo) == ServerNotificationPlan.Delivered(id: 3, recipient: recipient))
    }

    @Test
    func `A delivered notification that names no account is read back without one`() {
        #expect(ServerNotificationContent.delivered(identifier: "server-notification-9", userInfo: [ServerNotificationContent.linkKey: "https://cloud.example.com/apps/files/"]) == ServerNotificationPlan.Delivered(id: 9, recipient: nil))
    }

    @Test
    func `A delivered notification that is not a server notification is not read back as one`() {
        #expect(ServerNotificationContent.delivered(identifier: "web-notification-chat", userInfo: [:]) == nil)
    }

    @Test
    func `Only string values are read out of a notification's userInfo`() {
        let strings = ServerNotificationContent.strings(from: ["kept": "value", "number": 3, 4: "key not a string"])

        #expect(strings == ["kept": "value"])
    }
}
