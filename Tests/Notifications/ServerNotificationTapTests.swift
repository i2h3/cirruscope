// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerNotificationTapTests` covers what a tap on a server notification opens.
///
/// It exists because a notification outlives the session it was posted in: a tap arriving after a sign-out, or after somebody else signed in to the same server, must open nothing, and an address that does not stay on the signed-in server must never be loaded with that account's app password attached.
///
struct ServerNotificationTapTests {
    ///
    /// `aliceLink` is the `userInfo` of a notification posted for `alice` that opens a Talk conversation.
    ///
    private static let aliceLink = ServerNotificationContent.userInfo(for: ServerNotificationFixture.item(5, link: "/apps/spreed/call/abc"), to: ServerNotificationRecipient(ServerNotificationFixture.alice))

    @Test
    func `A tap on a notification for the account signed in opens its address`() {
        guard case let .open(target) = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: Self.aliceLink, signedIn: ServerNotificationFixture.alice) else {
            Issue.record("Expected the tap to open the notification's address")
            return
        }

        #expect(target.url.absoluteString == "https://cloud.example.com/apps/spreed/call/abc")
    }

    @Test
    func `A new app password for the same login still opens the notification`() {
        guard case .open = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: Self.aliceLink, signedIn: ServerNotificationFixture.aliceNewPassword) else {
            Issue.record("Expected the tap to open the notification's address")
            return
        }
    }

    @Test(arguments: [ServerNotificationFixture.bob, ServerNotificationFixture.otherServer])
    func `A tap on a notification posted for another account opens nothing`(signedIn: ServerAccount) {
        guard case .otherAccount = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: Self.aliceLink, signedIn: signedIn) else {
            Issue.record("Expected the tap to be refused as another account's")
            return
        }
    }

    @Test
    func `A tap while nobody is signed in opens nothing`() {
        guard case .notSignedIn = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: Self.aliceLink, signedIn: nil) else {
            Issue.record("Expected the tap to be refused for nobody being signed in")
            return
        }
    }

    @Test(arguments: [[:], [ServerNotificationContent.linkKey: ""]] as [[String: String]])
    func `A notification without an address is told apart from a refused one`(userInfo: [String: String]) {
        guard case .noLink = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: userInfo, signedIn: ServerNotificationFixture.alice) else {
            Issue.record("Expected the tap to find no address")
            return
        }
    }

    @Test
    func `A notification delivered before notifications recorded their account opens once its address is proven again`() {
        let legacy = [ServerNotificationContent.linkKey: "https://cloud.example.com/apps/files/"]

        guard case let .open(target) = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: legacy, signedIn: ServerNotificationFixture.alice) else {
            Issue.record("Expected the tap to open the notification's address")
            return
        }

        #expect(target.url.absoluteString == "https://cloud.example.com/apps/files/")
    }

    @Test
    func `An address that leaves the signed-in server is refused even for the right account`() {
        var tampered = Self.aliceLink
        tampered[ServerNotificationContent.linkKey] = "https://evil.example/steal"

        guard case .offOrigin = ServerNotificationTap.resolve(identifier: "server-notification-5", userInfo: tampered, signedIn: ServerNotificationFixture.alice) else {
            Issue.record("Expected the tap to refuse an address off the server")
            return
        }
    }

    @Test(arguments: ["0D9F1E2C-3B4A-4C5D-8E6F-7A8B9C0D1E2F", "web-notification-server-notification-5"])
    func `A tap on a notification that is not the server's is left to the app that posted it`(identifier: String) {
        guard case .notServerNotification = ServerNotificationTap.resolve(identifier: identifier, userInfo: Self.aliceLink, signedIn: ServerNotificationFixture.alice) else {
            Issue.record("Expected the tap to be recognized as not a server notification")
            return
        }
    }
}
