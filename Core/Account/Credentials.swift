// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `Credentials` bundles the Nextcloud login name and app password obtained from a completed Login Flow v2 grant.
///
/// `Keychain` persists and retrieves values of this type, `ServerConnection.authenticated(address:)` reads them to build an authenticated `Rainmaker.Server`, and both apps' web views and `AssetCache`'s downloads read them to authenticate their requests via HTTP Basic authentication.
struct Credentials: Codable {
    /// `user` is the Nextcloud login name returned as the `name` of a `Rainmaker.LoginResult`.
    ///
    /// It is sent as the user component of the HTTP Basic authentication used for `Rainmaker.Server` requests, the embedded web views and the app's asset downloads.
    let user: String

    /// `appPassword` is the device-specific app password returned as the `password` of a `Rainmaker.LoginResult`.
    ///
    /// It authenticates requests in place of the account password and can be revoked on the server without affecting the account.
    let appPassword: String

    /// `basicAuthorizationValue` is the `Authorization` header value that authenticates a request the app builds itself with these credentials, whether it loads an embedded web view or downloads an asset.
    ///
    /// Nextcloud accepts the app password as HTTP Basic authentication and establishes a web session from it, so the web view is signed in without a separate in-page login. `WebViewController.authenticatedRequest(for:)` on macOS, `ServerAccount.authenticatedRequest(for:)` on iOS and `AssetCache`'s downloads all attach it; it lives on the value rather than at any call site so they cannot encode it differently.
    var basicAuthorizationValue: String {
        "Basic \(Data("\(user):\(appPassword)".utf8).base64EncodedString())"
    }
}
