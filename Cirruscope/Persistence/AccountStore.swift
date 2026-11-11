// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import os
import Rainmaker
import SwiftData
import WidgetKit

/// `AccountStore` is the main-actor repository over a SwiftData container, owning every read and write of the connected account's data and of what the user set up on this device.
///
/// The keyboard shortcuts and the appearance settings are the exception, and deliberately so: they are what the user set up on this device, so they are records of their own with no relationship to the account, which a sign-out deletes without touching them. They live in this same store and container all the same, so they migrate, and are quarantined, together with everything else.
@MainActor
final class AccountStore {
    /// `logger` records store activity under the `AccountStore` category.
    let logger = Logger(for: AccountStore.self)

    /// `container` is the SwiftData container this store owns every read and write of.
    private let container: ModelContainer

    /// `isReservedShortcut` reports whether a shortcut is already occupied by one of Cirruscope's own fixed menu items, which `shortcut(forAppID:)` consults to keep such a stored shortcut off the menus.
    let isReservedShortcut: @MainActor (KeyboardShortcutTransferObject) -> Bool

    /// `notifyChange` announces that one of the account's stored domains, or one of the device's own records — its keyboard shortcuts or its appearance settings — changed, so whatever draws it refreshes.
    let notifyChange: @MainActor (Notification.Name) -> Void

    /// `context` is the container's main-actor context, the single context this store ever touches.
    var context: ModelContext {
        container.mainContext
    }

    /// `cachedAccount` retains the single `Account` between calls so the hot `serverAddress` read path does not re-fetch on every navigation decision.
    private var cachedAccount: Account?

    /// `cachedPreferences` retains the single `DevicePreferences` between calls, because a web view reads the appearance several times every time it re-applies it.
    private var cachedPreferences: DevicePreferences?

    /// `lookedForPreferences` is `true` once the store has looked for the `DevicePreferences` record, so finding none is remembered as well as finding one.
    ///
    /// Most devices never make a choice and so never have the record; without this, every appearance read on them would be a fetch.
    private var lookedForPreferences = false

    /// `init(container:isReservedShortcut:notifyChange:)` builds a store over `container`, defaulting the two dependencies it reaches outside itself for to behaviour every platform can supply.
    init(container: ModelContainer, isReservedShortcut: @escaping @MainActor (KeyboardShortcutTransferObject) -> Bool = { _ in false }, notifyChange: @escaping @MainActor (Notification.Name) -> Void = { AccountStore.post($0) }) {
        self.container = container
        self.isReservedShortcut = isReservedShortcut
        self.notifyChange = notifyChange

        // Commit explicitly rather than relying on deferred autosave, which is insufficient for the cross-process
        // read contract and could otherwise fire at an `await` suspension point in the middle of a mutation.
        context.autosaveEnabled = false
    }

    // MARK: - Current Account

    /// `currentAccount(createIfNeeded:)` returns the single `Account`, fetching it once and caching it, and optionally inserting a fresh one when none exists yet.
    func currentAccount(createIfNeeded: Bool) -> Account? {
        if let cachedAccount {
            return cachedAccount
        }

        var descriptor = FetchDescriptor<Account>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            cachedAccount = existing
            return existing
        }

        guard createIfNeeded else {
            return nil
        }

        let account = Account()
        context.insert(account)
        cachedAccount = account
        return account
    }

    /// `save()` commits pending changes, logging rather than throwing on failure to match the app's existing fire-and-forget persistence behavior.
    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Could not save the account store: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `post(_:)` posts `name` on the next main-thread turn, and is the production default for `notifyChange`.
    static func post(_ name: Notification.Name) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    // MARK: - Server Address

    /// `serverAddress` is the URL of the connected server, or `nil` while none is configured.
    var serverAddress: URL? {
        currentAccount(createIfNeeded: false)?.serverAddress
    }

    /// `connect(to:)` records `address` as the connected server, creating the account record if needed.
    func connect(to address: URL) {
        logger.notice("Recording the connected server address")
        currentAccount(createIfNeeded: true)?.serverAddress = address
        save()
    }

    /// `adopt(serverAddress:)` records `address` as the connected server if the account does not already say so, and announces it when it writes.
    func adopt(serverAddress address: URL) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        guard account.serverAddress != address else {
            logger.debug("The recorded server address is already the one just used")
            return
        }

        if account.serverAddress == nil {
            logger.notice("The account record carried no server address; recording the one just used, which repairs a store written before the address was persisted")
        } else {
            logger.notice("The recorded server address is not the one just used; correcting it")
        }

        account.serverAddress = address
        save()

        // Two names, because two different things were wrong until this moment. Everything listing the apps
        // reads the store and is unaffected, but everything *drawing* an entity resolves its picture against
        // this address and has been answering nil — so the indexes hold entries with no artwork, and only a
        // donation redraws them.
        notifyChange(.serverAppsDidChange)
        notifyChange(.donatedArtworkDidChange)
    }

    /// `disconnect()` signs out: it deletes the account — cascading to every record that hangs off it — then forgets every cache describing the old server, clears the stored Login Flow v2 credentials and withdraws every notification the app delivered, so nothing that came from that server, or describes the people on it, remains in the store, the caches, the Spotlight index, the widget, Notification Center or the Keychain.
    func disconnect() {
        deleteAccount()
        forgetEverythingOutsideTheStore()
    }

    /// `forgetEverythingOutsideTheStore()` clears the stored credentials, empties every cache that describes the connected server or the people on it, forgets the record of the server's notifications already seen, withdraws every notification the app delivered, discards a request to open something of the account that nothing has served yet, and then asks WidgetKit to redraw the widget.
    ///
    /// The order is the point. The credentials go first, because the widget runs in a process of its own and reads them to decide whom to fetch for: a timeline that read them before this ran saves its rows either before the saved feed is cleared below, which removes them, or after the credentials are gone, which it checks for and takes them back itself. The notifications follow the same rule: a fetch admitted to the record before the credentials went is erased with the record, one arriving after is turned away because they are gone, and a notification posted after the withdrawal is taken back by the fetch that posted it, which asks again once it has posted. The widget is asked to redraw last, once nothing it could read would sign it in, because otherwise it draws what its last timeline held until WidgetKit next asks, which can be long after the account it shows has gone.
    private func forgetEverythingOutsideTheStore() {
        Keychain.clearAll()
        forgetCaches()
        ActivityFeedStore.clear()
        ServerNotificationLedger.shared.clear()
        ServerNotificationDispatcher.withdrawAll()
        EntityOpening.shared.discardPending()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `forgetCaches()` empties every cache of what the connected server sent: its branding and the app icons, and the pictures of the people on it.
    private func forgetCaches() {
        AssetCache.shared.clear()
        ServerAppIcons.shared.clear()
        ServerAvatars.shared.clear()
        ConversationAvatars.shared.clear()
    }

    /// `forgetCachesIfSignedOut()` empties the caches a sign-out empties, but only while nobody is signed in, for a download a sign-out overtook and which landed after it.
    ///
    /// A refresh already under way when the account signs out goes on downloading, and the caches it fills were emptied before it finished, so it calls this once its downloads are done and puts right what landed late.
    /// Nobody being signed in means the store records no server and the Keychain holds no credentials, both at once: a store without an address is also how an iOS install whose credentials predate the store begins, and emptying the caches from under an account that is signed in would only cost it its icons until the next refresh.
    /// A Keychain that cannot be read leaves the caches alone, for the same reason.
    func forgetCachesIfSignedOut() {
        guard serverAddress == nil else {
            return
        }

        guard (try? Keychain.storedAccounts())?.isEmpty == true else {
            return
        }

        logger.notice("Nobody is signed in, so emptying the caches again of whatever a refresh downloaded after the sign-out")
        forgetCaches()
    }

    /// `deleteAccount()` deletes the account record — cascading to every record that hangs off it — drops the memoized `cachedAccount`, commits, and announces every domain the account held; the keyboard shortcuts and the appearance settings hang off nothing and are left alone.
    func deleteAccount() {
        if let account = currentAccount(createIfNeeded: false) {
            logger.notice("Deleting the connected account and everything cascading from it")
            context.delete(account)
        } else {
            logger.notice("Asked to delete the connected account, of which there is none")
        }

        cachedAccount = nil
        save()
        notifyChange(.serverAppsDidChange)
        notifyChange(.conversationsDidChange)
        notifyChange(.notesDidChange)
        notifyChange(.collectivesDidChange)
        notifyChange(.currentUserDidChange)
    }

    // MARK: - Theming

    /// `themeBackground` is the connected server's `Theming` `background` value (an image URL string or a hex color), or `nil`.
    var themeBackground: String? {
        currentAccount(createIfNeeded: false)?.themeBackground
    }

    /// `themeLogo` is the connected server's instance logo URL, or `nil`.
    var themeLogo: URL? {
        currentAccount(createIfNeeded: false)?.themeLogo
    }

    /// `themeBackgroundPlain` is the connected server's `backgroundPlain` flag, or `nil`.
    var themeBackgroundPlain: Bool? {
        currentAccount(createIfNeeded: false)?.themeBackgroundPlain
    }

    /// `persist(theming:)` records the server's branding into the account and downloads the referenced assets into `AssetCache`.
    func persist(theming: Theming) async {
        let account = currentAccount(createIfNeeded: true)

        let backgroundURL = theming.backgroundPlain
            ? nil
            : URL(string: theming.background, relativeTo: account?.serverAddress)?.absoluteURL

        account?.themeBackground = backgroundURL?.absoluteString ?? theming.background
        account?.themeLogo = theming.logo
        account?.themeBackgroundPlain = theming.backgroundPlain
        save()

        if let backgroundURL, backgroundURL.scheme == "http" || backgroundURL.scheme == "https" {
            do {
                try await AssetCache.shared.cache(remote: backgroundURL)
            } catch {
                logger.notice("Could not cache theming background: \(error.localizedDescription)")
            }
        }

        do {
            try await AssetCache.shared.cache(remote: theming.logo)
        } catch {
            logger.notice("Could not cache theming logo: \(error.localizedDescription)")
        }
    }

    // MARK: - Appearance

    /// `currentPreferences(createIfNeeded:)` returns the single `DevicePreferences`, fetching it once and caching it, and optionally inserting a fresh one when none exists yet.
    private func currentPreferences(createIfNeeded: Bool) -> DevicePreferences? {
        if let cachedPreferences {
            return cachedPreferences
        }

        if lookedForPreferences == false {
            var descriptor = FetchDescriptor<DevicePreferences>()
            descriptor.fetchLimit = 1
            cachedPreferences = try? context.fetch(descriptor).first
            lookedForPreferences = true

            if let cachedPreferences {
                return cachedPreferences
            }
        }

        guard createIfNeeded else {
            return nil
        }

        let preferences = DevicePreferences()
        context.insert(preferences)
        cachedPreferences = preferences
        return preferences
    }

    /// `translucentAppearance` is the user's choice to let the macOS window material show through the web view, or `nil` when the user has not chosen — in which case callers apply the app default (off). `WebViewController` reads it to drive both the injected stylesheet and the native backdrop's visibility.
    var translucentAppearance: Bool? {
        currentPreferences(createIfNeeded: false)?.translucentAppearance
    }

    /// `setTranslucentAppearance(_:)` records whether the translucent appearance is enabled on this device, then announces `Notification.Name.appearanceSettingsDidChange` so open web views re-apply it without a reload.
    func setTranslucentAppearance(_ enabled: Bool) {
        currentPreferences(createIfNeeded: true)?.translucentAppearance = enabled
        save()
        notifyChange(.appearanceSettingsDidChange)
    }

    /// `removeGaps` is the user's choice to expand Nextcloud's content to the window edges, or `nil` when the user has not chosen — in which case callers apply the app default (on).
    var removeGaps: Bool? {
        currentPreferences(createIfNeeded: false)?.removeGaps
    }

    /// `setRemoveGaps(_:)` records whether the content gaps are removed on this device, then announces `Notification.Name.appearanceSettingsDidChange` so open web views re-apply it without a reload.
    func setRemoveGaps(_ enabled: Bool) {
        currentPreferences(createIfNeeded: true)?.removeGaps = enabled
        save()
        notifyChange(.appearanceSettingsDidChange)
    }

    // MARK: - Server Version

    /// `serverVersion` is the human-readable version string of the connected server, or `nil`.
    var serverVersion: String? {
        currentAccount(createIfNeeded: false)?.serverVersion
    }

    /// `setServerVersion(_:)` records the connected server's version string.
    func setServerVersion(_ version: String?) {
        currentAccount(createIfNeeded: true)?.serverVersion = version
        save()
    }

    // MARK: - Current User

    /// `userPhotoSize` is the size the account's own picture is downloaded and read at, declared once so the refresh and every surface drawing the picture cannot disagree: the large rendition, since the smaller one is drawn blurred by both apps' buttons and settings at their screens' scales.
    nonisolated static let userPhotoSize = AvatarSize.large

    /// `userID` is the identifier the server keys the signed-in account by, or `nil` until the server has been asked.
    var userID: String? {
        currentAccount(createIfNeeded: false)?.userID
    }

    /// `userDisplayName` is the name the server displays for the signed-in account, or `nil` until the server has been asked.
    var userDisplayName: String? {
        currentAccount(createIfNeeded: false)?.userDisplayName
    }

    /// `userPhoto` is the photograph the signed-in account uploaded, read from the cache it was downloaded into, or `nil` when it has none, it has not been downloaded yet, or the account's identifier is not known yet.
    var userPhoto: CGImage? {
        guard let serverAddress else {
            return nil
        }

        guard let userID else {
            return nil
        }

        return ServerAvatars.shared.image(forUserID: userID, serverAddress: serverAddress, size: Self.userPhotoSize)
    }

    /// `setUser(id:displayName:)` records who the account signs in as, then announces `Notification.Name.currentUserDidChange` when anything changed.
    func setUser(id: String, displayName: String) {
        guard let account = currentAccount(createIfNeeded: false) else {
            logger.notice("Asked to record who the account signs in as, but there is no account to record it on")
            return
        }

        guard account.userID != id || account.userDisplayName != displayName else {
            logger.debug("Who the account signs in as is already recorded")
            return
        }

        account.userID = id
        account.userDisplayName = displayName
        save()
        logger.notice("Recorded who the account signs in as")
        notifyChange(.currentUserDidChange)
    }

    // MARK: - Server Apps

    /// `serverApps` is the connected server's apps as value snapshots, in the one order every surface lists them in: alphabetically by localized name, with the app identifier settling a tie.
    var serverApps: [ServerAppTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.apps
            .map { ServerAppTransferObject(id: $0.appID, order: $0.order, href: $0.href, name: $0.name) }
            .sortedByName()
    }

    /// `serverApp(forID:)` is the connected server's app with `appID` as a value snapshot, or `nil` when the account offers no such app.
    func serverApp(forID appID: String) -> ServerAppTransferObject? {
        guard let app = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID }) else {
            return nil
        }

        return ServerAppTransferObject(id: app.appID, order: app.order, href: app.href, name: app.name)
    }

    /// `persist(serverApps:)` upserts the server's apps: existing rows are updated in place, new ones inserted, and ones the server no longer offers deleted.
    func persist(serverApps: [ServerAppTransferObject]) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        // Snapshot the current apps before inserting, so the deletion pass iterates a stable list.
        let existingApps = account.apps
        var existingByID: [String: ServerApp] = [:]
        for app in existingApps {
            existingByID[app.appID] = app
        }

        var incomingIDs: Set<String> = []
        var inserted = 0
        var updated = 0
        var pruned = 0

        // Skip an id already seen in this list rather than inserting a second row for it: two rows sharing one id
        // would leave `serverApps`' name-then-identifier ordering with a tie it cannot break, and two menu items
        // would then claim the one shortcut recorded for that id. No real server sends duplicates.
        for item in serverApps where incomingIDs.contains(item.id) == false {
            incomingIDs.insert(item.id)

            if let existing = existingByID[item.id] {
                existing.order = item.order
                existing.href = item.href
                existing.name = item.name
                updated += 1
            } else {
                context.insert(ServerApp(appID: item.id, order: item.order, href: item.href, name: item.name, account: account))
                inserted += 1
            }
        }

        for app in existingApps where incomingIDs.contains(app.appID) == false {
            context.delete(app)
            pruned += 1
        }

        logger.notice("Persisting server apps: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated, \(pruned, privacy: .public) pruned, \(incomingIDs.count, privacy: .public) stored")
        save()
        notifyChange(.serverAppsDidChange)
    }

    // MARK: - Keyboard Shortcuts

    // The reads that decide which app a keystroke actually reaches are not here. They compare through
    // `ShortcutMatching`, which is a statement about how AppKit matches key equivalents and could not follow this
    // store into a folder iOS also compiles, so they live in `macOS/Persistence/AccountStore+KeyboardShortcuts.swift`.
    // What stays is the storage: reading the shortcuts out of the records, and writing one back.

    /// `storedShortcuts` are the shortcuts recorded on this device for the apps the connected server offers, each paired with its app, in the order the menus list those apps.
    var storedShortcuts: [(appID: String, name: String, shortcut: KeyboardShortcutTransferObject)] {
        let records = (try? context.fetch(FetchDescriptor<KeyboardShortcut>())) ?? []

        var shortcutsByAppID: [String: KeyboardShortcutTransferObject] = [:]

        for record in records {
            shortcutsByAppID[record.appID] = KeyboardShortcutTransferObject(keyEquivalent: record.keyEquivalent, modifierFlags: record.modifierFlags)
        }

        return serverApps.compactMap { app in
            guard let shortcut = shortcutsByAppID[app.id] else {
                return nil
            }

            return (app.id, app.name, shortcut)
        }
    }

    /// `storedShortcut(forAppID:)` is the shortcut recorded on this device for the app with `appID`, whether or not the connected server offers that app, or `nil` when none is.
    func storedShortcut(forAppID appID: String) -> KeyboardShortcutTransferObject? {
        guard let record = shortcutRecord(forAppID: appID) else {
            return nil
        }

        return KeyboardShortcutTransferObject(keyEquivalent: record.keyEquivalent, modifierFlags: record.modifierFlags)
    }

    /// `shortcutRecord(forAppID:)` is the `KeyboardShortcut` record for `appID`, or `nil` when none exists.
    private func shortcutRecord(forAppID appID: String) -> KeyboardShortcut? {
        var descriptor = FetchDescriptor<KeyboardShortcut>(predicate: #Predicate { $0.appID == appID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// `setShortcut(_:forAppID:)` assigns, replaces, or (when `shortcut` is `nil`) clears the keyboard shortcut of the app with `appID` on this device, then announces `Notification.Name.keyboardShortcutsDidChange` so the menus and the Keyboard Shortcuts tab update.
    func setShortcut(_ shortcut: KeyboardShortcutTransferObject?, forAppID appID: String) {
        let existing = shortcutRecord(forAppID: appID)

        if let shortcut {
            if let existing {
                existing.keyEquivalent = shortcut.keyEquivalent
                existing.modifierFlags = shortcut.modifierFlags
            } else {
                context.insert(KeyboardShortcut(appID: appID, keyEquivalent: shortcut.keyEquivalent, modifierFlags: shortcut.modifierFlags))
            }
        } else if let existing {
            context.delete(existing)
        } else {
            return
        }

        save()
        notifyChange(.keyboardShortcutsDidChange)
    }
}
