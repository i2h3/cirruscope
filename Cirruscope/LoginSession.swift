// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AuthenticationServices
import Foundation
import os
import Rainmaker

/// `LoginSession` runs Nextcloud's Login Flow v2 against one server: it presents the grant page in an `ASWebAuthenticationSession` and concurrently polls the login endpoint until the user completes the grant.
@MainActor
final class LoginSession: NSObject {
    /// `anchor` is the window the grant sheet is presented from, returned as-is by `presentationAnchor(for:)`.
    private let anchor: ASPresentationAnchor

    /// `authenticationSession` retains the `ASWebAuthenticationSession` that presents the Login Flow v2 grant page while polling is in progress.
    private var authenticationSession: ASWebAuthenticationSession?

    /// `authenticationCancelled` is set by the `ASWebAuthenticationSession` completion handler when the user dismisses the grant sheet, signaling `pollForCredentials(on:flow:)` to stop.
    private var authenticationCancelled = false

    /// `logger` records the sign-in flow under the `LoginSession` category.
    private let logger = Logger(for: LoginSession.self)

    private init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    /// `signIn(to:anchoredTo:)` runs one Login Flow v2 attempt against `server`, presenting the grant sheet from `anchor`, and returns the credentials the grant produced.
    static func signIn(to server: Server, anchoredTo anchor: ASPresentationAnchor) async throws -> LoginResult {
        let attempt = LoginSession(anchor: anchor)

        return try await attempt.signIn(to: server)
    }

    /// `signIn(to:)` runs Nextcloud's Login Flow v2 against `server` and returns the credentials the grant produced.
    private func signIn(to server: Server) async throws -> LoginResult {
        let flow = try await server.login()

        defer {
            dismissAuthenticationSession()
        }

        try startAuthenticationSession(using: flow.entry)

        return try await pollForCredentials(on: server, flow: flow)
    }

    /// `startAuthenticationSession(using:)` presents `url` in an `ASWebAuthenticationSession` so the user can authenticate and grant access.
    private func startAuthenticationSession(using url: URL) throws {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nc", completionHandler: makeAuthenticationCompletionHandler())

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true

        authenticationCancelled = false
        authenticationSession = session

        guard session.start() else {
            logger.error("Could not present the authentication session")
            throw CirruscopeError.loginPresentationFailed
        }
    }

    /// `makeAuthenticationCompletionHandler()` builds the completion handler `startAuthenticationSession(using:)` passes to its `ASWebAuthenticationSession`.
    private nonisolated func makeAuthenticationCompletionHandler() -> (URL?, (any Error)?) -> Void {
        { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.logger.debug("Authentication sheet dismissed by the user")
                self?.authenticationCancelled = true
            }
        }
    }

    /// `pollForCredentials(on:flow:)` polls `server`'s login endpoint until the user completes the grant, returning the resulting credentials.
    private func pollForCredentials(on server: Server, flow: LoginFlow) async throws -> LoginResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(300))

        while clock.now < deadline {
            try Task.checkCancellation()

            if authenticationCancelled {
                throw CirruscopeError.loginCancelled
            }

            if let result = try? await server.poll(flow) {
                logger.debug("Sign-in granted; received credentials")
                return result
            }

            try await Task.sleep(for: .seconds(1))
        }

        logger.error("Sign-in timed out after 300 seconds")
        throw CirruscopeError.loginTimedOut
    }

    /// `dismissAuthenticationSession()` cancels and releases the `ASWebAuthenticationSession`, dismissing the grant sheet once the login has completed, failed, or been cancelled.
    private func dismissAuthenticationSession() {
        authenticationSession?.cancel()
        authenticationSession = nil
    }
}

/// `LoginSession`'s conformance to `ASWebAuthenticationPresentationContextProviding` anchors the Login Flow v2 grant sheet to whichever window the caller named.
extension LoginSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
