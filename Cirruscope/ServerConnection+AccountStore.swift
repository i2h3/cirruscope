// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s app half: the parts of talking to a server that also write what was learned to `AccountStore`.
extension ServerConnection {
    /// `validateAndPersist(_:)` validates `server` and records what the validation found: its theming, and — when the version is supported — its version string.
    static func validateAndPersist(_ server: Server) async throws -> ValidationOutcome {
        let outcome = try await validate(server)

        let capabilities = switch outcome {
            case let .supported(capabilities): capabilities
            case let .unsupported(capabilities): capabilities
        }

        let theming = try? capabilities.get(Theming.self)

        if theming == nil {
            logger.debug("No theming capability present")
        }

        let version: String? = if case .supported = outcome {
            capabilities.version.string
        } else {
            nil
        }

        await recordValidation(theming: theming, version: version, of: server.address, as: credentials(of: server))

        return outcome
    }

    /// `recordValidation(theming:version:of:as:)` records what a validation of the server at `address` found, and for one made with `credentials` only while that account is still signed in.
    @MainActor
    private static func recordValidation(theming: Theming?, version: String?, of address: URL, as credentials: Credentials?) async {
        let isAuthenticated = credentials != nil

        defer {
            if isAuthenticated {
                AccountStore.shared.forgetCachesIfSignedOut()
            }
        }

        if let theming {
            guard isAuthenticated == false || mayRecord("the server's theming", fetchedFrom: address, as: credentials) else {
                return
            }

            await AccountStore.shared.persist(theming: theming)
        }

        if let version {
            guard isAuthenticated == false || mayRecord("the server's version", fetchedFrom: address, as: credentials) else {
                return
            }

            AccountStore.shared.setServerVersion(version)
        }
    }

    /// `refreshNavigationApps(using:)` fetches the server's navigation apps with the authenticated `server` and persists them via `AccountStore.persist(serverApps:)`.
    ///
    /// Failures are ignored because the apps list is non-critical: when it cannot be fetched the previously persisted list is simply left in place.
    static func refreshNavigationApps(using server: Server) async {
        let address = server.address
        let credentials = credentials(of: server)

        // Before the fetch rather than after it: this is the one path that runs on every activation while holding a
        // server the account is signed in to, so it is where a store that never learned its own address gets one.
        // It asks the Keychain alone whether that account is still signed in, the store's own answer being the one
        // that may need repairing, and a refresh that finds it is not asks the server for no app list.
        let adopted = await record("the server address", fetchedFrom: address, as: credentials, requiringStoredAccount: false) {
            AccountStore.shared.adopt(serverAddress: address)
        }

        guard adopted else {
            return
        }

        do {
            let items = try await server.navigation()
            let apps = items.map { ServerAppTransferObject(id: $0.id, order: $0.order, href: $0.href, name: $0.name) }

            let recorded = await record("the app list", fetchedFrom: address, as: credentials) {
                AccountStore.shared.persist(serverApps: apps)
            }

            guard recorded else {
                return
            }

            await refreshServerAppIcons(from: items, using: server)
        } catch {
            logger.notice("Could not refresh navigation apps; keeping the previous list: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `pageLanguage` is the language the connected server last rendered a signed-in page in, across every web view the app has open.
    ///
    /// One record serves every window and scene, so two of them finishing a page in the new language at once still refresh the list once: the first to report it changes the record on the main actor before the second is asked.
    @MainActor
    private static var pageLanguage = PageLanguage()

    /// `pageFinishedLoading(in:)` refreshes the app list when a page that has just finished loading was rendered in another language than the one before it, which is how a language changed in Nextcloud's personal settings, or on another device, reaches the menus, the Keyboard Shortcuts settings tab, Spotlight and the Shortcuts app (issue #138).
    @MainActor
    static func pageFinishedLoading(in language: String?) async {
        let previous = pageLanguage.current

        guard pageLanguage.adopt(language) else {
            logger.debug("A page finished loading in \(language ?? "no account language", privacy: .public), no change from \(previous ?? "none seen yet", privacy: .public); the app list is left as it is")
            return
        }

        guard let address = AccountStore.shared.serverAddress else {
            logger.notice("A page arrived rendered in \(language ?? "", privacy: .public) rather than \(previous ?? "", privacy: .public), but no server address is recorded; the app list is left as it is")
            return
        }

        guard let server = authenticated(address: address) else {
            logger.notice("A page arrived rendered in \(language ?? "", privacy: .public) rather than \(previous ?? "", privacy: .public), but no credentials are stored for the server; the app list is left as it is")
            return
        }

        logger.notice("A page arrived rendered in \(language ?? "", privacy: .public) rather than \(previous ?? "", privacy: .public); refreshing the app list so every surface names the apps in it")
        await refreshNavigationApps(using: server)
    }

    /// `refreshServerAppIcons(from:using:)` downloads the icon of every app the server just listed, and announces the app list again once they have landed.
    private static func refreshServerAppIcons(from items: [NavigationItem], using server: Server) async {
        guard let credentials = Keychain.credentials(for: server.address) else {
            logger.notice("No credentials are stored for the server whose apps were just listed; not fetching their icons")
            return
        }

        let didFetchAny = await ServerAppIcons.shared.refresh(items, serverAddress: server.address, credentials: credentials)

        // A sign-out while the icons were downloading has emptied the caches already, and an icon that landed after
        // it would otherwise outlive it.
        await AccountStore.shared.forgetCachesIfSignedOut()

        guard didFetchAny else {
            return
        }

        // Posted on the main actor, not from here. `NotificationCenter` delivers synchronously on the
        // posting thread, and every observer of this — `AppDelegate.rebuildServerAppsMenu()`, the Keyboard Shortcuts
        // settings tab, `ServerAppIndexer` — is main-actor-isolated, so posting from this task's own
        // executor trips Swift's isolation check and takes the process down. The store's own announcements,
        // made through `AccountStore.post(_:)`, are delivered on the main thread as well.
        await MainActor.run {
            NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)

            // The other domains wear these icons too — a note is drawn with the Notes mark, a conversation with
            // Talk's — and none of them observes the app list. Without this second name they stay pictureless
            // until their own data next changes, which on a first launch is not until the next refresh.
            NotificationCenter.default.post(name: .donatedArtworkDidChange, object: nil)
        }
    }

    /// `refreshCurrentUser(using:)` asks the authenticated `server` who the account signs in as, records the answer via `AccountStore.setUser(id:displayName:)`, and downloads the account's own photograph, announcing it once it has landed.
    static func refreshCurrentUser(using server: Server) async {
        let address = server.address
        let credentials = credentials(of: server)

        guard await isStillSignedIn(at: address, as: credentials) else {
            logger.notice("The account this refresh was begun for is no longer signed in; not asking who it signs in as")
            return
        }

        let user: User

        do {
            user = try await server.currentUser()
        } catch {
            logger.notice("Could not ask who the account signs in as; keeping what was recorded: \(error.localizedDescription, privacy: .public)")
            return
        }

        let recorded = await record("who the account signs in as", fetchedFrom: address, as: credentials) {
            AccountStore.shared.setUser(id: user.id, displayName: user.displayName)
        }

        guard recorded else {
            return
        }

        // Asked again even when the server drew a monogram for the account earlier in this process: an app runs for
        // weeks, and a picture uploaded meanwhile should appear on the next refresh rather than after a relaunch.
        await ServerAvatars.shared.refresh(userIDs: [user.id], size: AccountStore.userPhotoSize, on: server, askingAgain: true)

        // A sign-out while the picture was downloading has emptied the caches already, and a picture that landed after
        // it would otherwise outlive the account it shows.
        await AccountStore.shared.forgetCachesIfSignedOut()

        logger.notice("Refreshed who the account signs in as and its picture")

        // Posted on the main actor for the reason `refreshServerAppIcons(from:using:)` gives.
        await MainActor.run {
            NotificationCenter.default.post(name: .currentUserDidChange, object: nil)
        }
    }

    /// `credentials(of:)` is the login name and app password `server` signs its requests with, or `nil` for an anonymous server.
    ///
    /// They are the credentials a refresh fetched as, captured when the server was built, which is why they are read off the server rather than out of the Keychain: the Keychain says who is signed in now, and the two are compared before anything fetched is written.
    static func credentials(of server: Server) -> Credentials? {
        guard let user = server.user else {
            return nil
        }

        guard let password = server.password else {
            return nil
        }

        return Credentials(user: user, appPassword: password)
    }

    /// `admission(ofWhatWasFetchedFrom:as:requiringStoredAccount:)` reads what the Keychain and the store hold now and decides whether what a refresh fetched from `address` as `credentials` may be written.
    @MainActor
    static func admission(ofWhatWasFetchedFrom address: URL, as credentials: Credentials?, requiringStoredAccount: Bool) -> RefreshAdmission {
        let storedCredentials: Credentials?

        do {
            storedCredentials = try Keychain.storedCredentials(for: address)
        } catch {
            logger.error("Could not read the Keychain to confirm who is signed in: \(error.localizedDescription, privacy: .public)")
            return .keychainUnreadable
        }

        guard requiringStoredAccount else {
            return .forAdopting(fetchedAs: credentials, keychainHolds: storedCredentials)
        }

        return .forRecording(fetchedFrom: address, as: credentials, keychainHolds: storedCredentials, storeHolds: AccountStore.shared.serverAddress)
    }

    /// `isStillSignedIn(_:)` is whether the account `server` was built for is still the one signed in, for work that writes nothing but should not begin for an account that is gone.
    @MainActor
    static func isStillSignedIn(_ server: Server) -> Bool {
        isStillSignedIn(at: server.address, as: credentials(of: server))
    }

    /// `isStillSignedIn(at:as:)` is whether the account signed in as `credentials` at `address` is still the one signed in.
    ///
    /// A refresh asks it before each fetch as well as before each write, so one a sign-out overtook stops sending the signed-out account's app password to the server rather than only discarding what it brings back.
    @MainActor
    static func isStillSignedIn(at address: URL, as credentials: Credentials?) -> Bool {
        guard case .admitted = admission(ofWhatWasFetchedFrom: address, as: credentials, requiringStoredAccount: true) else {
            return false
        }

        return true
    }

    /// `mayRecord(_:fetchedFrom:as:requiringStoredAccount:)` is whether `what` — fetched from `address` as `credentials` — may be written, logging why not when it may not.
    @MainActor
    static func mayRecord(_ what: StaticString, fetchedFrom address: URL, as credentials: Credentials?, requiringStoredAccount: Bool = true) -> Bool {
        let admission = admission(ofWhatWasFetchedFrom: address, as: credentials, requiringStoredAccount: requiringStoredAccount)

        guard case .admitted = admission else {
            logger.notice("Not recording \(what, privacy: .public): \(String(describing: admission), privacy: .public)")
            return false
        }

        return true
    }

    /// `record(_:fetchedFrom:as:requiringStoredAccount:_:)` runs `write` only if the account a refresh fetched as is still the one signed in, and reports whether it ran.
    @discardableResult
    static func record(_ what: StaticString, fetchedFrom address: URL, as credentials: Credentials?, requiringStoredAccount: Bool = true, _ write: @MainActor @Sendable () -> Void) async -> Bool {
        await MainActor.run {
            guard mayRecord(what, fetchedFrom: address, as: credentials, requiringStoredAccount: requiringStoredAccount) else {
                return false
            }

            write()
            return true
        }
    }
}
