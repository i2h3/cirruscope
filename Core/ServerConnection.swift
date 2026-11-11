// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection` builds `Rainmaker.Server` instances and validates them, centralizing the connection logic both apps' sign-in paths share.
enum ServerConnection {
    /// `ValidationOutcome` reports the result of `validate(_:)`.
    enum ValidationOutcome {
        /// `supported` carries the capabilities of a server whose major version meets `InfoPlist.minimumSupportedServerMajorVersion`.
        case supported(CapabilitySet)

        /// `unsupported` carries the capabilities of a server whose major version is below `InfoPlist.minimumSupportedServerMajorVersion`.
        case unsupported(CapabilitySet)
    }

    /// `logger` records connection and validation activity under the `ServerConnection` category.
    static let logger = Logger(for: ServerConnection.self)

    /// `anonymous(address:)` builds a `Server` without credentials, used to validate reachability and to initiate Login Flow v2.
    static func anonymous(address: URL) -> Server {
        Server(address: address, userAgent: userAgent)
    }

    /// `authenticated(address:)` builds a `Server` carrying the credentials stored for `address`, or `nil` if none have been stored.
    static func authenticated(address: URL) -> Server? {
        guard let credentials = Keychain.credentials(for: address) else {
            return nil
        }

        return Server(address: address, password: credentials.appPassword, user: credentials.user, userAgent: userAgent)
    }

    /// `authenticated(_:)` builds a `Server` for `account`, carrying the credentials it already holds rather than reading them from the Keychain again.
    ///
    /// The widget extension uses it for everything a fetch does after it has resolved its account, which is what keeps a refresh to the one Keychain read that resolved it.
    static func authenticated(_ account: ServerAccount) -> Server {
        Server(address: account.server, password: account.credentials.appPassword, user: account.credentials.user, userAgent: userAgent)
    }

    /// `validate(_:)` fetches `server`'s capabilities and reports whether its major version meets `InfoPlist.minimumSupportedServerMajorVersion`.
    static func validate(_ server: Server) async throws -> ValidationOutcome {
        logger.info("Validating server capabilities")

        let capabilities = try await server.capabilities()
        let minimumMajorVersion = InfoPlist.minimumSupportedServerMajorVersion

        guard capabilities.version.major >= minimumMajorVersion else {
            logger.notice("Server version \(capabilities.version.string) is below the minimum \(minimumMajorVersion)")
            return .unsupported(capabilities)
        }

        logger.info("Server version \(capabilities.version.string) is supported")

        return .supported(capabilities)
    }

    /// `revokeAppPassword(using:)` asks the server to revoke the Login Flow v2 app password `server` is currently authenticated with, so the credential the app is about to discard locally is also invalidated on the server.
    static func revokeAppPassword(using server: Server) async {
        do {
            try await server.deleteAppPassword()
            logger.info("Revoked the app password on the server")
        } catch {
            logger.notice("Could not revoke the app password on the server; proceeding with local sign-out regardless: \(error.localizedDescription)")
        }
    }

    /// `verifyAppPassword(at:as:)` asks the server at `address` whether it still accepts `credentials`, by making one authenticated request with them and reading the answer.
    static func verifyAppPassword(at address: URL, as credentials: Credentials) async -> AppPasswordVerdict {
        let started = ContinuousClock.now
        let server = Server(address: address, password: credentials.appPassword, user: credentials.user, userAgent: userAgent)

        logger.notice("Asking the server whether it still accepts the stored app password")

        do {
            _ = try await server.currentUser()
            logger.notice("The server accepted the stored app password in \(Self.milliseconds(since: started), privacy: .public) ms")
            return .accepted
        } catch RainmakerError.unexpectedStatus(code: 401) {
            logger.notice("The server rejected the stored app password with HTTP 401 in \(Self.milliseconds(since: started), privacy: .public) ms")
            return .rejected
        } catch {
            logger.notice("Could not tell whether the server accepts the stored app password after \(Self.milliseconds(since: started), privacy: .public) ms: \(error.localizedDescription, privacy: .public)")
            return .undetermined
        }
    }

    /// `milliseconds(since:)` is how long ago `start` was, in whole milliseconds, for the durations `verifyAppPassword(at:as:)` logs.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }

    /// `userAgent` is the HTTP user agent Cirruscope presents to the server, taken from `InfoPlist.applicationName`.
    static var userAgent: String {
        InfoPlist.applicationName
    }
}
