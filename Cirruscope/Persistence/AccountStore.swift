// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftData
import WidgetKit

/// `AccountStore` is the main-actor repository over a SwiftData container, owning every read and write of the connected account's data and of what the user set up on this device.
///
/// It is the only place the account's server-related values are kept, none of them in `UserDefaults`. Consumers reach it as `AccountStore.shared`, mirroring the `AssetCache.shared` / `NotificationMonitor.shared` conventions, and it posts `Notification.Name.serverAppsDidChange` so every surface listing the apps refreshes. Each further domain — conversations, notes and collectives so far — is a section of this same type, in a file of its own, rather than a sibling store: every record describing the server hangs off the single `Account` this one memoizes, and a second store over the same container would memoize it again and go stale.
///
/// The keyboard shortcuts and the appearance settings are the exception, and deliberately so: they are what the user set up on this device, so they are records of their own with no relationship to the account, which a sign-out deletes without touching them. They live in this same store and container all the same, so they migrate, and are quarantined, together with everything else.
///
/// It is compiled into both apps. `shared` itself is not declared here but in a per-platform `AccountStore+Shared.swift`, because building the store means answering what counts as a reserved keyboard shortcut, and only macOS assigns shortcuts to server apps and so has that question to answer; the reads that consult that answer are likewise in `macOS/Persistence/AccountStore+KeyboardShortcuts.swift`.
///
/// Reads return value-type DTOs (`ServerAppTransferObject`, `KeyboardShortcutTransferObject`), never managed `@Model` objects, so AppKit table views and menus hold snapshots that stay valid across an upsert. Every access is confined to the main actor and only `Sendable` values ever cross the boundary to the nonisolated `ServerConnection`, which is what keeps the store race-free under Swift 6 complete concurrency. Autosave is disabled and each mutator saves explicitly, so every change commits atomically and is on disk by the time a future extension process reads it.
///
/// The container, and the two things this store reaches outside itself for, arrive through `init(container:isReservedShortcut:notifyChange:)` so its logic can be exercised against an in-memory store; the suites in `Tests/Account/` do exactly that, against both app modules. Production builds exactly one instance, `shared`.
@MainActor
final class AccountStore {
    /// `logger` records store activity under the `AccountStore` category.
    ///
    /// `internal` rather than `private` for the reason `ServerConnection.logger` is: this store is one type spread over a file per domain, and each of those files logs what it wrote. Under one category the whole of a refresh — fetched, persisted, announced, donated — reads as one story in a capture instead of as three unrelated ones.
    let logger = Logger(for: AccountStore.self)

    /// `container` is the SwiftData container this store owns every read and write of.
    ///
    /// It is held rather than reached for so it can be handed in, and because a `ModelContainer` closes its store once nothing references it any more.
    private let container: ModelContainer

    /// `isReservedShortcut` reports whether a shortcut is already occupied by one of Cirruscope's own fixed menu items, which `shortcut(forAppID:)` consults to keep such a stored shortcut off the menus.
    ///
    /// It is a closure rather than a direct call because the lookup behind it answers from the live `NSApp.mainMenu`, and the test bundle is hosted by the app: the real `Main.storyboard` menu bar is loaded for the whole test run, so a case using ⌘Z — which both "Undo" and "Redo" declare — would be measuring the storyboard instead of this store. A test hands in a closure naming exactly the combinations it means to reserve.
    /// It is `internal` rather than `private` because `shortcut(forAppID:)` reads it and lives in this store's macOS half, Swift's `private` being file-scoped.
    let isReservedShortcut: @MainActor (KeyboardShortcutTransferObject) -> Bool

    /// `notifyChange` announces that one of the account's stored domains, or one of the device's own records — its keyboard shortcuts or its appearance settings — changed, so whatever draws it refreshes.
    ///
    /// It is injected for the mirror image of `isReservedShortcut`'s reason: the hosted app keeps observers of these names alive for the whole of a test run.
    /// `AppDelegate` observes `Notification.Name.serverAppsDidChange` and `Notification.Name.keyboardShortcutsDidChange`, so a test write posting either would have the real `AppDelegate.rebuildServerAppsMenu()` read `shared` — the developer's actual account and shortcuts — and rewrite the live menu bar, on a main-queue turn no test can wait for.
    /// Every open `WebViewController` observes `Notification.Name.appearanceSettingsDidChange` and would re-apply the appearance from `shared` in the same way.
    /// A test hands in a closure that counts instead, which is also the only way to assert that a mutator announced at all, the production post being deliberately asynchronous. `post(_:)` is that production post.
    ///
    /// It takes the name rather than being one closure per domain. Every domain announces under a name of its own, and a seam that grew a parameter for each would put the cost of adding one in the initializer, in every call site of it, and in the test harness — which is how a seam stops being used. One name-taking closure means a new domain adds a name and nothing else.
    /// It is `internal` rather than `private` because the per-domain files that make up this store are files of their own, and Swift's `private` is file-scoped.
    let notifyChange: @MainActor (Notification.Name) -> Void

    /// `context` is the container's main-actor context, the single context this store ever touches.
    ///
    /// `internal` rather than `private` because this store is written as one type across several files, one per domain, and Swift's `private` is file-scoped. Nothing outside the store reaches it: every read hands back a value snapshot and every write takes one.
    var context: ModelContext {
        container.mainContext
    }

    /// `cachedAccount` retains the single `Account` between calls so the hot `serverAddress` read path does not re-fetch on every navigation decision.
    ///
    /// `AccountStore` is the sole mutator on the main actor, so the cache stays consistent; `deleteAccount()` clears it after deleting the record.
    private var cachedAccount: Account?

    /// `cachedPreferences` retains the single `DevicePreferences` between calls, because a web view reads the appearance several times every time it re-applies it.
    ///
    /// Nothing ever deletes the record and only this store inserts it, so unlike `cachedAccount` this memo, and `lookedForPreferences` beside it, need no reset.
    private var cachedPreferences: DevicePreferences?

    /// `lookedForPreferences` is `true` once the store has looked for the `DevicePreferences` record, so finding none is remembered as well as finding one.
    ///
    /// Most devices never make a choice and so never have the record; without this, every appearance read on them would be a fetch.
    private var lookedForPreferences = false

    /// `init(container:isReservedShortcut:notifyChange:)` builds a store over `container`, defaulting the two dependencies it reaches outside itself for to behaviour every platform can supply.
    ///
    /// A `ModelContainer` rather than a `ModelContext` is the parameter so that "the container's main-actor context" stays an invariant this store enforces, rather than something a caller could subvert by handing in a background context.
    /// `isReservedShortcut` defaults to reserving nothing, which is the truth on a platform that assigns no server-app shortcuts and would be a silent bug on one that assigns them without having installed the real lookup. That is why `shared` is built in a per-platform extension file rather than here: macOS passes the `AppDelegate` lookup as part of constructing the instance, so there is no window in which the store exists and answers "nothing is reserved".
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
    ///
    /// `internal` rather than `private` because this store's macOS half reads it, Swift's `private` being file-scoped.
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
    ///
    /// `internal` rather than `private` for the same reason `context` is: the per-domain files that make up this store are files of their own.
    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Could not save the account store: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `post(_:)` posts `name` on the next main-thread turn, and is the production default for `notifyChange`.
    ///
    /// The async hop is deliberate: it keeps the observers from running reentrantly inside the control that triggered the write — `AppDelegate.rebuildServerAppsMenu()` and `ServerAppsViewController.reload()` inside the `ShortcutRecorderView.onChange` handler, and every `WebViewController` re-applying the appearance inside the `NSSwitch` action handler in `AppearanceSettingsViewController`. It is `static` and not `private` so it can serve as that default argument, which may not reference a declaration less visible than the initializer itself — keeping this explanation next to the behaviour rather than inside a parameter list.
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
    ///
    /// `ServerAddressViewController` on macOS and `ServerAddressView` on iOS call it after a successful Login Flow v2 sign-in.
    func connect(to address: URL) {
        logger.notice("Recording the connected server address")
        currentAccount(createIfNeeded: true)?.serverAddress = address
        save()
    }

    /// `adopt(serverAddress:)` records `address` as the connected server if the account does not already say so, and announces it when it writes.
    ///
    /// It exists because `connect(to:)` is reached only from an interactive sign-in, while six other writers create the account record without it — `persist(serverApps:)`, `persist(theming:)`, `setServerVersion(_:)` and the three domain upserts all call `currentAccount(createIfNeeded: true)` and none of them records the address of the server they were just talking to. A fully populated account with no address is therefore a reachable state, and without this method a permanent one.
    /// iOS is where it is actually reached, because the two platforms disagree about who is authoritative for "am I signed in". macOS gates on this store, so an account with no address forces a fresh sign-in, which writes one. iOS gates on the Keychain, so a device whose credential predates the store keeps launching signed in, fills the store with apps and conversations and notes through those other writers, and never learns the address. The visible result is everything that reads it coming back empty: no artwork on any Spotlight result, and every intent refusing to open anything because there is nothing to resolve a route against.
    /// Called from the app-list refresh, which is the one path that runs on every activation, already holds a credentialed server and already creates the account record downstream — so an install in that state repairs itself on its next launch with nothing asked of the user.
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

    /// `disconnect()` signs out: it deletes the account — cascading to every record that hangs off it — then forgets every cache describing the old server and clears the stored Login Flow v2 credentials, so nothing that came from that server, or describes the people on it, remains in the store, the caches, the Spotlight index, the widget or the Keychain.
    ///
    /// It is the one sign-out there is: the Mac's `AppDelegate.logOut()` and `requireSignIn()`, the Mac's launch when it finds a server named but no credential stored for it, both of iOS's sign-outs and iOS's launch in the same state run it, so the list of what a sign-out forgets is written once. What the user set up on this device — the keyboard shortcuts and the appearance settings — has no relationship to the account and stays, ready for the next sign-in. The announcements happen in `deleteAccount()`, ahead of the clears rather than after them, which is unobservable inside this process: the posts are delivered on the next main-thread turn, while every clear is synchronous and finishes inside the current one.
    func disconnect() {
        deleteAccount()
        forgetEverythingOutsideTheStore()
    }

    /// `forgetEverythingOutsideTheStore()` clears the stored credentials, empties every cache that describes the connected server or the people on it, and then asks WidgetKit to redraw the widget.
    ///
    /// The order is the point. The credentials go first, because the widget runs in a process of its own and reads them to decide whom to fetch for: a timeline that read them before this ran saves its rows either before the saved feed is cleared below, which removes them, or after the credentials are gone, which it checks for and takes them back itself. The widget is asked to redraw last, once nothing it could read would sign it in, because otherwise it draws what its last timeline held until WidgetKit next asks, which can be long after the account it shows has gone.
    private func forgetEverythingOutsideTheStore() {
        Keychain.clearAll()
        AssetCache.shared.clear()
        ServerAppIcons.shared.clear()
        ServerAvatars.shared.clear()
        ConversationAvatars.shared.clear()
        ActivityFeedStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `deleteAccount()` deletes the account record — cascading to every record that hangs off it — drops the memoized `cachedAccount`, commits, and announces every domain the account held; the keyboard shortcuts and the appearance settings hang off nothing and are left alone.
    ///
    /// It is the storage half of `disconnect()`, separated so it can be exercised on its own: `disconnect()`'s remaining steps empty the shared caches and the widget's saved feed and clear the `Keychain`, none of which a test can run without destroying the developer's real cached assets and stored credentials. Clearing `cachedAccount` is what keeps a later write from landing on the deleted object instead of a fresh account.
    /// Each domain is announced under its own name because each Spotlight indexer listens for its own: announcing only the server apps left every conversation, note and collective of a signed-out account in the index.
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
    ///
    /// The metadata write and its save happen synchronously on the main actor; the asset downloads are awaited afterwards and run off the main actor, so a slow download never blocks it and cannot interleave with the commit. `ServerConnection.validateAndPersist(_:)` awaits this, and both paths that produce the first web window — `AppDelegate.presentInitialWindow(forLaunch:)` at launch and `ServerAddressViewController` after sign-in — await that validation before presenting, so the branding is cached before any UI relying on it is shown. A window opened later by ⌘N deliberately does not wait, reading the copy those paths already cached; `WebViewController.cachedBackgroundImage()` treats a miss as "no background available" rather than an error. The background download is skipped when `theming.background` is a color value rather than an `http`/`https` image URL.
    ///
    /// `theming.background` may be an absolute URL or a server-root-relative path — Nextcloud returns a relative path for backgrounds picked from its shipped gallery — so it is resolved against `account.serverAddress` before being stored and cached. Resolution is skipped when `theming.backgroundPlain` is `true`, since `background` then holds a color value (e.g. `"#00679e"`) that would otherwise resolve into a bogus fetchable URL (the server address with a `#`-fragment).
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

    /// `translucentAppearance` is the user's choice to let the macOS window material show through the web view, or `nil` when the user has not chosen — in which case callers apply the app default (off). `WebViewController` reads it to drive both the injected stylesheet and the native background image's visibility.
    var translucentAppearance: Bool? {
        currentPreferences(createIfNeeded: false)?.translucentAppearance
    }

    /// `setTranslucentAppearance(_:)` records whether the translucent appearance is enabled on this device, then announces `Notification.Name.appearanceSettingsDidChange` so open web views re-apply it without a reload.
    ///
    /// `AppearanceSettingsViewController` calls it from the translucent-appearance switch, which is reachable whether or not anybody is signed in; the choice is recorded on the device and never creates an account.
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
    ///
    /// `AppearanceSettingsViewController` calls it from the remove-gaps switch; like the translucency setter, it never creates an account.
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
    ///
    /// `ServerConnection.validateAndPersist(_:)` calls it once a supported server's capabilities are retrieved. It is a method rather than a settable property because `ServerConnection` is nonisolated and reaches it with `await` across the main-actor boundary.
    func setServerVersion(_ version: String?) {
        currentAccount(createIfNeeded: true)?.serverVersion = version
        save()
    }

    // MARK: - Server Apps

    /// `serverApps` is the connected server's apps as value snapshots, in the one order every surface lists them in: alphabetically by localized name, with the app identifier settling a tie.
    ///
    /// The sort is applied here rather than left to each caller for two reasons. SwiftData does not preserve the order of a to-many relationship, so the records arrive in no meaningful order and something has to impose one; and sorting once, at the single read every surface shares, is what keeps the View menu, the Dock menu (both built by `AppDelegate`), the Speed Dials settings tab (`ServerAppsViewController`), the Shortcuts and Siri lists (`ServerAppEntityQuery`), the Spotlight index (`ServerAppIndexer`), `storedShortcuts` — which walks this list — and on iOS `Store.apps`, which the iPhone's title menu and the iPad's View menu both draw, from being able to disagree about where an app sits. Each of those consumers arrived without having to know the rule, which is the point of the sort living at the read rather than in any of them. The server's own position for an app, `ServerAppTransferObject.order`, deliberately decides nothing here: it arranges the web interface's app menu, where it reads as a layout the admin chose, while a native menu is scanned for a name.
    ///
    /// The comparison itself is `sortedByName()`, applied nowhere else: iOS reads this same property rather than sorting for itself, so the two apps cannot list the apps differently; its own documentation says why the collation is `localizedStandardCompare(_:)` and why the identifier settles a tie. That totality matters here specifically: two apps a server offers under one name would otherwise be free to swap places between two menu rebuilds, taking which of them a duplicate shortcut reaches with them, `appHolding(_:)` reading the first match.
    var serverApps: [ServerAppTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.apps
            .map { ServerAppTransferObject(id: $0.appID, order: $0.order, href: $0.href, name: $0.name) }
            .sortedByName()
    }

    /// `serverApp(forID:)` is the connected server's app with `appID` as a value snapshot, or `nil` when the account offers no such app.
    ///
    /// It is the single-app counterpart of `serverApps`: `ServerAppEntityQuery.entities(for:)` and `EntityActivation` resolve a donated or saved app id back to a `ServerAppTransferObject` through it, and `ServerConnection.refreshCollectives(using:)` asks it whether the server offers the Collectives app at all. Like every other read here it returns a value-type DTO, never the managed `ServerApp`.
    func serverApp(forID appID: String) -> ServerAppTransferObject? {
        guard let app = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID }) else {
            return nil
        }

        return ServerAppTransferObject(id: app.appID, order: app.order, href: app.href, name: app.name)
    }

    /// `persist(serverApps:)` upserts the server's apps: existing rows are updated in place, new ones inserted, and ones the server no longer offers deleted.
    ///
    /// Pruning an app leaves its keyboard shortcut alone, the shortcut being keyed by the app's identifier rather than belonging to the record, so it applies again whenever a later refresh lists the app. `ServerConnection.refreshNavigationApps(using:)` calls it with the `Rainmaker.NavigationItem`s it fetched already mapped to this app's own value type, so the store's write side speaks the same type its read side returns and neither depends on the shape of the network library — which is also what lets a test seed an app list without the test target linking that library.
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
    ///
    /// `internal` rather than `private` because `appHolding(_:)` walks it and lives in this store's macOS half, Swift's `private` being file-scoped.
    /// It walks `serverApps` rather than sorting the records itself, so that order is the menus' own by construction — alphabetical by name, with the app identifier breaking a tie so that it is total. `appHolding(_:)` reads the first match from it to decide which single app a shared shortcut reaches, and that answer has to be the same on every call rather than depend on an unstable sort.
    /// Walking the offered apps is also the rule for a shortcut whose app the server does not offer: it is left out, so it reaches nothing, takes part in no conflict and is named as nobody's occupant, until a refresh lists its app again.
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
    ///
    /// It is the raw record, with none of the rules `shortcut(forAppID:)` applies before a shortcut reaches a menu.
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

    /// `setShortcut(_:forAppID:)` assigns, replaces, or (when `shortcut` is `nil`) clears the keyboard shortcut of the app with `appID` on this device, then announces `Notification.Name.keyboardShortcutsDidChange` so the menus and the Speed Dials tab update.
    ///
    /// `ServerAppsViewController` calls it from each row's `ShortcutRecorderView`. It records against the identifier alone, needing neither an account nor the app being offered: the shortcut belongs to the device, and applies wherever and whenever a server offers an app with that identifier.
    ///
    /// It deliberately stores whatever it is given: rejecting a shortcut another app or a fixed menu item already occupies is the caller's job, done while recording (see `nameOfApp(usingShortcut:otherThanAppID:)` and `AppDelegate.reservedShortcutName(for:)`), so the settings tab can explain the rejection where the user is looking instead of a write silently doing nothing. Should a duplicate be stored anyway — by a future caller, or by an app returning to a server that offers another app the same shortcut was recorded for meanwhile — `shortcut(forAppID:)` still keeps it off the menus.
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
