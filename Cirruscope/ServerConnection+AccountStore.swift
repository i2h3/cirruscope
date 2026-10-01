// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s app half: the parts of talking to a server that also write what was learned to `AccountStore`.
///
/// `ServerConnection` itself lives in `Core/` and is compiled into the widget extension as well as both apps, so it can depend on nothing the extension does not compile — and `AccountStore` is a main-actor SwiftData store only the apps have. This extension is where that dependency is allowed to exist, which is why it sits in `Cirruscope/` rather than beside the type it extends.
/// Both apps call it. macOS refreshes the app list from `AppDelegate` and `ServerAddressViewController`, and iOS from `Store.updateApps()`, so the list every menu on either platform draws is persisted the same way; `validateAndPersist(_:)` and `isStillSignedIn(_:)` are the parts only macOS calls.
/// It is also where every refresh, its per-domain siblings' included, has its writes admitted: `record(_:fetchedFrom:as:requiringStoredAccount:_:)` asks `RefreshAdmission` whether the account a refresh fetched as is still the one signed in, in the same main-actor turn as the write it allows.
extension ServerConnection {
    /// `validateAndPersist(_:)` validates `server` and records what the validation found: its theming, and — when the version is supported — its version string.
    ///
    /// It is what `AppDelegate` and `ServerAddressViewController` call in place of `validate(_:)`, and it returns that call's outcome unchanged, so they switch over the same `ValidationOutcome` that iOS's `ServerAddressView` gets from `validate(_:)` directly.
    /// Theming is persisted on both branches, an unsupported server's appearance being still the appearance of the server the user is looking at an alert about.
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
    ///
    /// An anonymous validation is the Mac's sign-in, made before there is an account to ask about, and what it found is recorded regardless, the first web window opened after the sign-in drawing its backdrop from it.
    /// An authenticated one is the Mac's launch and every web window it opens afterwards, and a sign-out can overtake it like any refresh, so it is asked about before each write.
    /// Whichever way it ends, the caches are then emptied again if nobody is signed in by then, the theming downloads being the likeliest thing a sign-out overtakes.
    /// It is isolated to the main actor so that each question and the write after it happen in one turn: `persist(theming:)` writes before it first suspends, and nothing can sign out in between.
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
    ///
    /// Mapping `Rainmaker.NavigationItem` to `ServerAppTransferObject` happens here, at the boundary where the network library is already in scope, rather than inside the store or on the transfer object itself — the store then depends on nothing but the app's own value types, and the transfer object stays free of logic.
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

    /// `refreshServerAppIcons(from:using:)` downloads the icon of every app the server just listed, and announces the app list again once they have landed.
    ///
    /// This is the only moment the app learns where an icon lives: the path is part of a navigation response and is deliberately not persisted, since a menu finds an icon again by the app's identifier rather than by where it came from. Fetching here rather than where the menus are built is what keeps the Dock menu — which AppKit asks for and draws in the same breath — free of anything it would have to wait for.
    /// The second announcement is what redraws the menus with the icons in them; `persist(serverApps:)` has already made the first. It is sent only when something was actually fetched, so an unchanged app list does not rebuild every menu to look exactly as it already did. A third name goes out beside it for the domains that draw these icons without owning them — see `Notification.Name.donatedArtworkDidChange`.
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
        // posting thread, and every observer of this — `AppDelegate.rebuildServerAppsMenu()`, the Speed Dials
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
    ///
    /// `requiringStoredAccount` is `false` only for recording the address itself, which is how a store that lost it is repaired and so cannot be required to agree already.
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
    ///
    /// The question and the write happen in one turn of the main actor, which is why the write is handed over as a closure rather than made by the caller afterwards: the store and every sign-out run on the main actor too, so a sign-out cannot fall between the answer and the write it allows.
    /// Every write a refresh makes goes through it, deletions included: a `404` from a server nobody is signed in to any longer says nothing about the account that is.
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
