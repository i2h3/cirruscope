// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `ServerNotificationRecipient` is the account a server notification was fetched as, named by the server and the login name and never by the app password.
///
/// It is what binds a notification in Notification Center, and the record of the notifications already seen, to one account, so a later sign-in to the same server as somebody else neither inherits the record nor opens the previous account's links.
/// The login name is the one the account signs in with, never the addressee a notification names: the two can differ, and only the first is something the app holds for certain.
/// It leaves the app password out because it is written into a file and into every notification's `userInfo`, neither of which is a place for a credential.
/// It lives in `Cirruscope/` with the rest of the notification code both apps run, the widget extension having no use for it.
///
struct ServerNotificationRecipient: Codable, Hashable, Sendable {
    ///
    /// `server` is the root address of the server the notifications were fetched from.
    ///
    let server: URL

    ///
    /// `loginName` is the login name the account signs in with.
    ///
    let loginName: String

    ///
    /// `init(server:loginName:)` names a recipient by its two halves.
    ///
    init(server: URL, loginName: String) {
        self.server = server
        self.loginName = loginName
    }

    ///
    /// `init(_:)` names the recipient `account` stands for, dropping its app password.
    ///
    init(_ account: ServerAccount) {
        server = account.server
        loginName = account.credentials.user
    }
}
