// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `Credentials` bundles the Nextcloud login name and app password obtained from a completed Login Flow v2 grant.
struct Credentials: Codable, Equatable {
    /// `user` is the Nextcloud login name returned as the `name` of a `Rainmaker.LoginResult`.
    let user: String

    /// `appPassword` is the device-specific app password returned as the `password` of a `Rainmaker.LoginResult`.
    ///
    /// It authenticates requests in place of the account password and can be revoked on the server without affecting the account.
    let appPassword: String

    /// `basicAuthorizationValue` is the `Authorization` header value that authenticates a request the app builds itself with these credentials, whether it loads an embedded web view or downloads an asset.
    var basicAuthorizationValue: String {
        "Basic \(Data("\(user):\(appPassword)".utf8).base64EncodedString())"
    }
}
