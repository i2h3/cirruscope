// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerNotificationRecipient` is the account a server notification was fetched as, named by the server and the login name and never by the app password.
struct ServerNotificationRecipient: Codable, Hashable, Sendable {
    /// `server` is the root address of the server the notifications were fetched from.
    let server: URL

    /// `loginName` is the login name the account signs in with.
    let loginName: String

    /// `init(server:loginName:)` names a recipient by its two halves.
    init(server: URL, loginName: String) {
        self.server = server
        self.loginName = loginName
    }

    /// `init(_:)` names the recipient `account` stands for, dropping its app password.
    init(_ account: ServerAccount) {
        server = account.server
        loginName = account.credentials.user
    }
}
