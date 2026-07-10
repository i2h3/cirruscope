// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection` builds `Rainmaker.Server` instances and validates them, centralizing the connection logic shared by `AppDelegate` and `ServerAddressViewController`.
///
/// `anonymous(address:)` is used before the user has authenticated and to initiate Login Flow v2, `authenticated(address:)` builds a credentialed server from `Keychain`, and `validate(_:)` fetches capabilities, persists theming, and reports whether the server's version is supported.
enum ServerConnection {
    /// `ValidationOutcome` reports the result of `validate(_:)`.
    enum ValidationOutcome {
        /// `supported` carries the fetched `CapabilitySet` of a server whose major version meets `Settings.minimumSupportedServerMajorVersion`.
        case supported(CapabilitySet)

        /// `unsupported` carries the human-readable version string of a server whose major version is below `Settings.minimumSupportedServerMajorVersion`.
        case unsupported(version: String)
    }

    /// `logger` records connection and validation activity under the `ServerConnection` category.
    private static let logger = Logger(for: ServerConnection.self)

    /// `anonymous(address:)` builds a `Server` without credentials, used to validate reachability and to initiate Login Flow v2.
    static func anonymous(address: URL) -> Server {
        Server(address: address, userAgent: userAgent)
    }

    /// `authenticated(address:)` builds a `Server` carrying the credentials stored for `address`, or `nil` if none have been stored.
    ///
    /// The returned server can call authenticated endpoints such as `navigation()`.
    static func authenticated(address: URL) -> Server? {
        guard let credentials = Keychain.credentials(for: address) else {
            return nil
        }

        return Server(address: address, password: credentials.appPassword, user: credentials.user, userAgent: userAgent)
    }

    /// `validate(_:)` fetches `server`'s capabilities, persists its theming, and reports whether its major version is supported, recording the version string of a supported server in `Settings.serverVersion`.
    ///
    /// It rethrows any error raised while fetching the capabilities so callers can distinguish an unreachable or unauthorized server from an unsupported one.
    static func validate(_ server: Server) async throws -> ValidationOutcome {
        logger.info("Validating server capabilities")
        let capabilities = try await server.capabilities()

        if let theming = try? capabilities.get(Theming.self) {
            await Settings.persist(theming: theming)
        } else {
            logger.debug("No theming capability present")
        }

        let minimumMajorVersion = Settings.minimumSupportedServerMajorVersion

        guard capabilities.version.major >= minimumMajorVersion else {
            logger.notice("Server version \(capabilities.version.string) is below the minimum \(minimumMajorVersion)")
            return .unsupported(version: capabilities.version.string)
        }

        Settings.serverVersion = capabilities.version.string
        logger.info("Server version \(capabilities.version.string) is supported")

        return .supported(capabilities)
    }

    /// `refreshNavigationApps(using:)` fetches the server's navigation apps with the authenticated `server` and persists them via `Settings.persist(navigationApps:)`.
    ///
    /// Failures are ignored because the apps list is non-critical: when it cannot be fetched the previously persisted list is simply left in place.
    static func refreshNavigationApps(using server: Server) async {
        do {
            let apps = try await server.navigation()
            Settings.persist(navigationApps: apps)
        } catch {
            logger.notice("Could not refresh navigation apps; keeping the previous list: \(error.localizedDescription)")
        }
    }

    /// `userAgent` is the HTTP user agent Cirruscope presents to the server, derived from the app's bundle name.
    private static var userAgent: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cirruscope"
    }
}
