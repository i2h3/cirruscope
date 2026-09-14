// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `ServerAccount` is a Nextcloud server address together with the credentials that authenticate against it — the two halves of one `Keychain` item, which files a `Credentials` value under the address it belongs to.
///
struct ServerAccount {
    /// `server` is the root address of the Nextcloud server, as the server itself reported it in the Login Flow v2 result.
    let server: URL

    /// `credentials` are the login name and app password that authenticate against `server`.
    let credentials: Credentials

    /// `authenticatedRequest(for:)` is the request that loads `url` with this account's app password attached as HTTP Basic authentication.
    ///
    /// Nextcloud accepts an app password as Basic authentication on any page and establishes a web session from it, which is how the embedded web view is signed in without a second, in-page login after the native one.
    /// It attaches the header unconditionally, and the rule that nothing receives the credential without first having been proven to stay on `server` therefore belongs to the caller, which resolves what it is about to request through `SameOriginURL`. Keeping the two apart is deliberate: there is then one place that knows how the credential is spelled, and the proof stays where the untrusted address actually arrives.
    func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(credentials.basicAuthorizationValue, forHTTPHeaderField: "Authorization")

        return request
    }
}
