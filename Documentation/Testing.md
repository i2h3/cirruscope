<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Testing

This is the reference half of [AGENTS.md → Testing](../AGENTS.md#testing): how the test targets are wired, which suites cover which domain, how the account store is put under test, what the host apps do during a run, and what stays untested and why.
The rules themselves are in that section and are not restated here.

## Targets and schemes

- `macOSTests/` and `iOSTests/` are each a test target with its own `.xcconfig`.
  `Tests/` is listed by both and carries no `.xcconfig`, so every suite in it runs twice, once against each app module.
  That is not redundancy: `Core/` and `Cirruscope/` are compiled twice, against two SDKs, and a framework can answer differently on each, which a suite pinned to one platform cannot see.
- Both test targets are hosted by their app: `project.pbxproj` sets `TEST_HOST` to `$(BUILT_PRODUCTS_DIR)/Cirruscope.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cirruscope` and `BUNDLE_LOADER` to `$(TEST_HOST)`.
  A suite therefore reaches the app's internal types through `@testable import Cirruscope`, and a macOS suite may touch AppKit directly.
  The host app runs for the whole test run, which is what most of this document is about.
- `Cirruscope for macOS.xcscheme` and `Cirruscope for iOS.xcscheme` are committed in `Cirruscope.xcodeproj/xcshareddata/xcschemes/`, so each scheme's test action is the same everywhere rather than depending on the per-user schemes Xcode autocreates (`xcuserdata` is gitignored).
- In Xcode, Product ▸ Test (⌘U) runs exactly the same suites as the scheme selected.
  The `xcodebuild test` commands in [AGENTS.md → Testing](../AGENTS.md#testing) are for a terminal session, and Xcode Cloud, the project's CI, builds and tests from the same shared schemes.
- The iOS command names a concrete Simulator rather than the generic destination a build takes, because a test action has to run somewhere.
- Both commands carry `-allowProvisioningUpdates` because a test run signs for real, and automatic signing may register identifiers and fetch profiles from the command line only when it is allowed to; see [AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing).
  The test bundles include only the root `Cirruscope.xcconfig`, so they carry no entitlements of their own; see [BuildingAndSigning.md](./BuildingAndSigning.md).
- Tests run in Debug because `@testable import` needs the testability that the Release configuration does not enable.
- `macOSTests/macOSTests.xcconfig` and `iOSTests/iOSTests.xcconfig` set `SWIFT_EMIT_LOC_STRINGS = NO`, so tests contribute no localized strings and the string-catalog check stays about the app's own strings.
- Swift Testing builds a fresh suite instance for every case, so a harness held as a stored property belongs to that case alone, and it runs a suite's cases in parallel unless the suite is `.serialized`.

## Suite map

Each suite's documentation comment says what it covers and why it exists; this map is for finding it.
Names are file names without `.swift`.
The root a suite goes under follows the code under test, per [AGENTS.md → Testing](../AGENTS.md#testing), so one domain can span roots: `Tests/ServerAddress/` holds the two pure suites, and `macOSTests/ServerAddress/` the one driving a real `NSTextField`, because the split follows what a suite *needs*, not what it is about.
Domain names match the ones `Core/` uses, except that the suites over `Core/RemoteAssets/SVG/` sit in `Tests/Icons/`, beside those over `Core/SameOriginURL.swift`.

### `Tests/`, run against both app modules

- `Account/`: `ServerAppUpsertTests` (`AccountStore.persist(serverApps:)` updates in place by identifier and prunes, and the `serverApps` snapshot's order is total and localized, a property of the snapshot rather than of any one menu), `ConnectedAccountTests` (the account's lifecycle, the `cachedAccount` reset, which domains a deletion announces, and what survives it), `RefreshAdmissionTests` (whether a refresh a sign-out overtook may still write; a matching address alone is not enough), `AppPasswordVerdictTests` (which answer about an app password signs out which account), `KeychainEnumerationTests` (the enumeration's query shapes against both Keychains, the file-based one answering `errSecParam` to `kSecReturnData` with `kSecMatchLimitAll`, over a service nothing is filed under) and `StoreImportTests` (`AppDatabase.importStore(from:into:)` moving the store and its sidecars into the App Group container and quarantining what is there, and a `1.1.0`-shaped store moved that way still migrating with everything in it, with two `StoreFileHarness` instances as the two containers).
  `StoreMigrationTests` reopens a store written by each shipped schema, seeded through that version's frozen models, at the current one through `CirruscopeMigrationPlan`.
  It is `.serialized` because the plan carries state between `willMigrate` and `didMigrate` process-wide, and deliberately not `@MainActor`, because a synchronous migration on the main actor deadlocked the run.
  Its `1.0.0` case is disabled, since seeding and migrating that store in one process aborts the test host whenever another suite runs beside it, until a store written by a real `1.0.0` build is committed as its fixture.
  Its case for a store left at the intermediate `SchemaV2_1` step pins that an interrupted migration still finishes.
- `Activity/`: `ActivityRowTests` (how an activity becomes a row, through the string functions `ActivityRow.init(_:)` decides with), `ActivityVerbTests` (which activity types get a badge and which are refused) and `ActivityFeedSnapshotTests` (a saved feed written before it recorded its server still decodes).
- `AppIntents/`: `EntityIdentifierRoundTripTests` (what App Intents' own identifier carries), `SpotlightSelectionTests` (what a tapped Spotlight result resolves to, for each of the five types), `EntityActivationTests` (what each identifier activates), `EntityOpeningLatchTests` (the latch holding a request that arrives before any screen exists), `EntityOpeningPrecedenceTests` (which of several windows' openers serves one) and `ShortcutsNameTests` (the action titles and entity type names the Shortcuts app lists are translated in every shipped localization, the type names cased as names).
- `Appearance/`: `DevicePreferencesTests` (the appearance settings as the store keeps them, apart from any account).
- `Collectives/`, `Conversations/` and `Notes/`: a shared fixture each (`CollectiveFixture`, `ConversationFixture`, `NoteFixture`) and three suites each, `…PersistenceTests` (what the store does with a refresh's results), `…SortingTests` (how the domain is ordered) and `…WebRouteTests` (the address that opens one of its items).
- `Configuration/`: `KeychainServiceIdentifierTests` (the Keychain service identifier read from `Info.plist` equals the app's bundle identifier) and `UsageDescriptionTests` (the reasons each app's property list gives for the camera, the microphone and the local network).
- `Icons/`: `SVGPathDataTests`, `SVGTransformTests`, `SVGGlyphTests` and `SVGGlyphRasterizationTests` (the SVG renderer), `SameOriginURLTests` and `SameOriginURLComponentsTests` (resolving a path the server named, appending one the app knows, and that the two disagree), `ConversationAvatarFreshnessTests` (when a conversation's cached picture is asked about again, over an `AssetCache(directory:)` of its own) and `PlatedArtworkTests` (the donated plate filled with an emoji or a conversation's own picture, asserted as colour and opacity rather than shape).
- `Notifications/`: `UnreadNotificationsBadgeUpdateTests` (what an unread-count fetch means for the badge).
- `ServerAddress/`: `ServerAddressTests` (what a typed or pasted address normalizes to) and `ServerAddressEndpointDerivationTests` (the Foundation behaviour that rests on).
- `ServerApps/`: `ServerAppPathTests` (a URL read as a path on one instance), `ServerAppResolutionTests` (which app a page belongs to) and `PageTitleTests` (the page-title shortening the resolution falls back to).
- `Theming/`: `ThemeColorTests` (the plain background color a server's theming names).
- `WebView/`, the six decisions both web views share: `NextcloudSessionRouteTests` (the server's two session routes, and the address a sign-in form's `redirect_url` names), `SignOutRequestTests` (whether a navigation to the sign-out route is the user's or the page's own), `WebViewDestinationTests` (whether an address is the web view's to display or the system's to open), `SilentRetryBudgetTests` (what a web view does while it works through a lapsed session, its property cases asserting that only the server's own refusal of the app password ever signs out), `MediaCaptureDecisionTests` (which pages get the camera and the microphone) and `PageLanguageTests` (whether a finished page's language means the account's language changed).
  It also measures the three WebKit facts those decisions, and the script keeping a page's local storage, rest on.
  `ScriptNavigationSupersessionTests` asserts that a navigation the page's own script starts supersedes an app-initiated load whose navigation-policy decision is still pending, which is why a redirect to the sign-in form after a retry is never read as the app password being refused; its probe navigates the page in each of the ways `ScriptNavigationTrigger` names and records each run as a `ScriptNavigationSupersessionOutcome` of `NavigationCallback`s.
  `SignOutNavigationTypeTests` asserts the navigation type WebKit reports for each of the ways `NavigationTypeTrigger` names of reaching the sign-out route, which is what tells Nextcloud's own "Log out" from its session heartbeat; its probe records each run as a `NavigationTypeOutcome` holding a `RecordedNavigationAction`, with its `NavigationActionTarget`, for every action its navigation delegate was asked to decide, and the type of every new-window request its UI delegate received.
  `LocalStorageRetentionTests` asserts that `Script.localStorageRetention`, installed at document start in the main frame as both apps install it, keeps a page's own call clearing local storage from removing anything, against a control in which the same page empties it.

### `macOSTests/`

- `Account/`: the store's keyboard shortcuts, which need AppKit because a shortcut there is a `ShortcutFixture` built from `NSEvent.ModifierFlags`, in `AppShortcutAssignmentTests` (recording, replacing and clearing one app's shortcut), `DuplicateShortcutSuppressionTests` (the first app in menu order wins a shared shortcut, on every call, issue #64) and `ShortcutSurvivalTests` (a shortcut outlives its app being updated or pruned and the account being deleted, and applies again when a server offers the app), with `ReservedShortcuts`.
  `FileBasedKeychainMoveTests` covers `Keychain.moveFileBasedItems(service:)`, which only macOS makes, and first measures the three framework facts it rests on.
  A query that leaves `kSecUseDataProtectionKeychain` out reaches the data-protection Keychain as well, for a read and for a deletion alike, which the first version of the move did not know, and so it deleted the copy it had just made.
  With the flag set either way, an item in one Keychain is invisible from the other.
  And a deletion with the flag set to `false` leaves the data-protection item in place.
  It then pins the move itself: a file-based credential moves, an existing data-protection credential is kept while the stale file-based copy is removed, a leftover for another server is removed rather than copied beside the credential already there, nothing to move touches nothing, and a second move finds nothing left.
- `Appearance/`: `WebAccentColorTests` (the hex-string shape the accent color crosses into JavaScript as, and the brightness threshold it shares with Nextcloud's `Util::invertTextColor()`), `WebAccentColorForwardingTests` (the decision withholding the app's own accent color, issue #93) and `MulticolorAccentColorOracleTests`.
  The last measures AppKit: the asset `NSAccentColorName` names resolves to the shipped values, and `controlAccentColor` answers with it while the macOS accent color is "Multicolor", against the global `AppleAccentColor` default as an oracle only a test reads.
  Its second case runs only on a machine set to "Multicolor", and it is how `WebAccentColor.effective(in:)` is covered, by agreement rather than by value, since that reads whichever accent color the test machine has chosen.
- `Icons/`: `ServerAppIconThumbnailTests` (the donated artwork for a server app, a white window plate with the app's glyph in it, asserted as colour and opacity rather than shape).
  It is a macOS suite because the glyph's ink is the one part each platform answers for itself, here `NSColor.secondaryLabelColor` resolved in the light appearance, and resolving it in the wrong appearance is one of the ways the artwork goes wrong.
- `KeyboardShortcuts/`: `ShortcutMatchingTests`, `ShortcutDisplayStringTests` and `KeyEquivalentMatchingOracleTests`, with `ShortcutFixture` and `KeyEquivalentProbe`.
- `ServerAddress/`: `ServerAddressFieldNormalizationTests` (drives a real `NSTextField` carrying `ServerAddressFormatter` to pin when AppKit applies it).
- `Windows/`: `WebWindowFrameTests` (the fullscreen rule, and `NSWindow.saveFrame(usingName:)`/`setFrameUsingName(_:)` measured against a second, freshly created window, issue #82), `NextcloudHeaderHeightTests` (which reported header heights are believed, what survives the round trip through `UserDefaults`, and which reports are announced, issue #102), `WebWindowButtonPlacementTests` (a window button's center coincides with the header's whatever either measures, the property a compiled-in height could not hold) and `WebWindowButtonClearanceTests` (issue #95).
  The last asserts that fullscreen needs no clearance, that whatever is answered leaves the last button behind it, and, against a window button AppKit itself vends, that an ordinary window's answer is still the number `macOS/Cirruscope.css` falls back to.

### `iOSTests/`

- `Notifications/`: `NotificationRefreshTaskConfigurationTests` (reads the built property list to confirm the background refresh is configured the way the system requires, since SwiftUI's `.backgroundTask(_:)` does not pass on whether `BGTaskScheduler` accepted the identifier).
- `WebView/`: `WebPageInsetsTests` (the value type turning a SwiftUI measurement into the call publishing it into the page) and `SafariUserAgentTests`, with `SafariUserAgentProbe`.
- Everything shared the target runs comes from `Tests/`.

### Probes and oracles

Each is the measure-then-agree shape [AGENTS.md → Testing](../AGENTS.md#testing) asks for, and none needs a server or the network.

- `KeyEquivalentProbe` (`macOSTests/KeyboardShortcuts/`) hands `NSMenu.performKeyEquivalent(with:)` a synthesized key-down event against a throwaway one-item menu; `KeyEquivalentMatchingOracleTests` holds `ShortcutMatching.areEquivalent(_:_:)` to it for every pair of `ShortcutFixture.all`.
- `SecurityOriginProbe` (`Tests/WebView/`) reports the security origin a real `WKWebView` gives a document, in WebKit's own spelling of scheme, host and port, for `MediaCaptureDecisionTests`.
- `ScriptNavigationSupersessionProbe` (`Tests/WebView/`) holds the navigation-action decision of a load the app asked for while the page navigates itself, then releases it, for `ScriptNavigationSupersessionTests`, whose first case is the control in which the page does not navigate.
- `NavigationTypeProbe` (`Tests/WebView/`) makes a page reach the sign-out route and cancels a main-frame action so the page never leaves, for `SignOutNavigationTypeTests`.
  A test cannot synthesize a trusted click, so a user's click is approximated by a script the app evaluates calling the link's `click()`.
- `LocalStorageClearProbe` (`Tests/WebView/`) loads a page that stores an item and clears local storage, with or without a user script installed ahead of it, and reports through an alert how many items are left, for `LocalStorageRetentionTests`.
- `SafariUserAgentProbe` (`iOSTests/WebView/`) loads `about:blank` into a real `WebPage` and reports the user agent it tells a page, for `SafariUserAgentTests`.
- `RecordingURLSchemeHandler` (`Tests/WebView/`) stands in for a server for both navigation probes: it answers every request under its scheme from memory and records each path, so a request is recorded only if WebKit actually made it, and it answers a poll path with HTTP 200 until `rejectsPolls` is set and HTTP 401 afterwards.
- `SplitMix64` (`Tests/WebView/`) is the fixed-seed generator behind `SilentRetryBudgetTests`' property cases, so a failure names the seed that reproduces it; it deliberately does not conform to `RandomNumberGenerator`, so no standard library algorithm stands between a seed and its numbers.
- The four `WKWebView` probes use a non-persistent data store, and the four suites driving them carry a five-minute `.timeLimit`, which turns a report that never arrives into a failure rather than a run that never ends.
- These suites measure a framework without a probe type: `KeychainEnumerationTests` and the first three cases of `FileBasedKeychainMoveTests` (the Keychains), `SVGGlyphRasterizationTests` (Core Graphics), `ServerAddressEndpointDerivationTests` (`URL(string:)`), `ServerAddressFieldNormalizationTests` (when AppKit runs a formatter), `WebWindowFrameTests` and `WebWindowButtonClearanceTests` (`NSWindow`), and `MulticolorAccentColorOracleTests` (the accent color).

### Harnesses and fixtures

- `AccountStoreHarness` (`Tests/Account/`) is one `AccountStore` over a private in-memory container built from the app's current schema.
  It answers the reserved-shortcut lookup with the closure it was given, reserving nothing by default, and counts announcements in `notificationCount`, recording their names in `announcements`.
  The count says that a mutator announced, not when: the production post hops to the next main-thread turn and the harness deliberately does not, so a case can assert it synchronously.
- `StoreFileHarness` (`Tests/Account/`) gives one case a store on disk in a directory of its own under `URL.temporaryDirectory`, removed when the case ends, because a migration reopens a store written earlier and an in-memory container is never reopened.
- `KeychainScratchService` (`macOSTests/Account/`) gives one case a Keychain service of its own in both Keychains, with as many accounts under it as the case needs, and deletes everything filed under it from both when the case ends, so no case ever touches `Keychain.service`, where the developer's real credentials are.
- `ReservedShortcuts` (`macOSTests/Account/`) builds the reserved-shortcut closure that the assignment and duplicate-suppression suites hand `AccountStoreHarness`, out of `ShortcutMatching`, which is AppKit and so could not follow the harness into `Tests/`.
- `ServerAppFixture` (`Tests/Account/`) is the server-app corpus the account suites seed a store with, in the shape `AccountStore.persist(serverApps:)` takes.
- `ShortcutFixture` (`macOSTests/KeyboardShortcuts/`) is one named shortcut; its `all` is the corpus `ShortcutMatchingTests` and `KeyEquivalentMatchingOracleTests` share, and its `name` makes a failure print `⇧⌘Z` rather than a Private Use Area scalar.
- `SVGGlyphFixture` (`Tests/Icons/`) is hand-authored, each document reproducing a property measured from Nextcloud's own icons, which are AGPL-licensed and must never be committed into this MIT-licensed repository; `CGPathElements` is a comparable transcript of a `CGPath`, so the parser is asserted on the commands it produced rather than a bounding box.

## Why a case's post traps the host

The rule is in [AGENTS.md → Testing](../AGENTS.md#testing); this is the mechanism.

- The host app runs for the whole test run, a restored web window included, so a notification a case posts reaches the app's real observers.
- `NotificationCenter` runs an observer synchronously on the posting thread, so a main-actor observer reached from a suite Swift Testing runs off the main thread traps the host and fails every case scheduled after it as a crash.
- The poster therefore takes the post as a closure defaulting to the production one, and a case hands in one that counts calls, which is also the only way to assert an announcement at all, as `AccountStore.notifyChange` and `NextcloudHeaderHeight.record(_:key:notifyChange:)` do.
  Isolating the poster to the main actor as well, as the latter is, turns a call from a suite off the main thread into a compile error rather than a crash.
- `NextcloudHeaderHeightTests` is where it happened: before either, a real post from one of its cases reached a `WebWindowController`'s main-actor observer of `Notification.Name.nextcloudHeaderHeightDidChange` and trapped the host.

## Testing the account store

The rules are in [AGENTS.md → Testing](../AGENTS.md#testing), and the reasoning in [DECISIONS.md → "Why does the account store take its SwiftData container instead of reaching for the app's?"](../DECISIONS.md#why-does-the-account-store-take-its-swiftdata-container-instead-of-reaching-for-the-apps).

- `AccountStore` takes its `ModelContainer` through `init(container:isReservedShortcut:notifyChange:)`: `shared` passes `AppDatabase.container`, and each `AccountStoreHarness` an in-memory one, since nothing there tests file layout and an in-memory store leaves no cleanup a failing case could skip.
- `AccountStore.shared` is off limits because its container lives in the shared App Group container and holds the developer's real account, and `AppDatabase.container`'s recovery path moves the store files aside on a failed open and opens an empty store in their place.
  Being a `static let`, that container is opened only once something asks for it, so no suite opens it as long as none reaches `shared`.
- A second store over `AppDatabase.container` is off limits because each instance memoizes the single `Account` and the single `DevicePreferences` separately, so two of them over one container would each believe a stale answer.
- The store is shared, so the harness lives in `Tests/Account/` and runs against both app modules, as do the suites over it that need nothing platform-specific; `macOSTests/Account/` holds the part that needs AppKit, which is why the harness takes the reserved-shortcut stand-in as a closure rather than as a list of shortcuts it compares itself.
- The store's two reaches outside itself are injected as plain closures, with no protocols, no mock types and no `#if DEBUG`, because the test bundle is hosted by the app, which changes what a test may assume.
  - `isReservedShortcut` defaults to reserving nothing, which the iOS app's `shared` relies on, while the Mac app's `shared`, built in `macOS/Persistence/AccountStore+Shared.swift`, passes a wrapper around `AppDelegate.reservedShortcutName(for:)`, which answers from the live `NSApp.mainMenu`.
    The real menu bar is loaded for the whole run, so a case using ⌘Z against it would be measuring `Main.storyboard` rather than the store.
  - `notifyChange` takes the name of the domain that changed and defaults to `AccountStore.post(_:)`, the production post, which deliberately posts on the next main-thread turn.
    `AppDelegate` observes `Notification.Name.serverAppsDidChange` and `Notification.Name.keyboardShortcutsDidChange` for the whole run, every open `WebViewController` observes `Notification.Name.appearanceSettingsDidChange`, and the Spotlight indexers observe their own domains' names.
    A test write would otherwise have the live View menu rebuilt from `AccountStore.shared`, or a live window re-apply its appearance, on a main-queue turn no test controls.
- `AccountStore.persist(serverApps:)` takes the app's own `ServerAppTransferObject`, not `Rainmaker.NavigationItem`; the mapping lives in `ServerConnection.refreshNavigationApps(using:)`, so a test seeds an app list without linking Rainmaker, which neither test target does.
  The same constraint is why `ActivityRowTests` exercises the functions `ActivityRow.init(_:)` decides with, why `UnreadNotifications.badgeUpdate(forFetchedCount:)` is factored out, and why `ServerAddressEndpointDerivationTests` spells the paths `Server.init` appends as literals.

## Live state the suites stay away from

The host app keeps more than the store live, and the suites use stand-ins:

- `AppGroup.containerURL` and `AppDatabase.container`: the migration and import suites use `StoreFileHarness`, since the recovery path would quarantine the developer's real store the first time such a test failed.
- `EntityOpening.shared`, into which the host app installs a real opener for the whole run: the two `EntityOpening…Tests` build their own.
- `AssetCache.shared`: `ConversationAvatarFreshnessTests` uses an `AssetCache(directory:)` under `URL.temporaryDirectory`.
- `Keychain.service`: `FileBasedKeychainMoveTests` uses `KeychainScratchService`, and `KeychainEnumerationTests` a service nothing is filed under.
- `WebWindowFrame.defaultName` and `NextcloudHeaderHeight.defaultsKey`: their suites pass a name or key of their own to every case and clear it afterwards, so `UserDefaults` and the developer's own web windows are left as they were.

## What the host apps do during a run

- Each host app opens a store of its own during every test run regardless: on macOS `applicationDidFinishLaunching(_:)` → `rebuildServerAppsMenu()` → `AccountStore.shared.serverApps`, on iOS `iOSApp.init()` → `Store.restored()` → `AccountStore.shared.serverApps`.
  It is the real one in the App Group container, which on a developer's machine holds their own account unless the run was given a base identifier of its own; that is expected, not a regression.
- On iOS, `Store.restored()` also runs `AccountStore.shared.disconnect()` when the store names a server while the Keychain answers that it holds no credential, so a Simulator in that state is signed out as the host launches.
- Opening the store also runs the one-time import, `AppDatabase.importStore(from:into:)`, so the first test run on a Mac that still has a store in the app's own container, one an App Store `1.1.0` wrote, say, moves it into the App Group container, exactly as the first launch of an entitled build would.
  Run with a base identifier of your own when that move is the thing you are about to test.
- The macOS host also makes the move out of the file-based Keychain in `applicationWillFinishLaunching(_:)`, and under the shipping base identifier what it moves is the developer's real credentials.
  So the first macOS test run on a Mac whose credentials are still in the file-based Keychain moves them into the data-protection Keychain, or deletes them if that Keychain already holds a credential, after which a build still reading the file-based Keychain, an older TestFlight or App Store build, finds none.
- `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest -allowProvisioningUpdates`, or a contributor's own base identifier with `.citest` appended, keeps all of this off the developer's data, the move looking only under the Keychain service that identifier derives; [BuildingAndSigning.md](./BuildingAndSigning.md) has what else it isolates.
- A run confirms that no test wrote through the store by leaving the store file's modification time untouched.
  `AppDatabase` logs the file's path at `.notice` as it opens it, as "Opened the SwiftData store in the App Group container at …" under the `AppDatabase` category; [Logging.md](./Logging.md) has how to read it.

## Deliberately untested in the store

[AGENTS.md → Testing](../AGENTS.md#testing) names what stays out; this is the full list with the reasons, and [DECISIONS.md → "Why are only parts of the app unit-tested?"](../DECISIONS.md#why-are-only-parts-of-the-app-unit-tested) explains where the line sits.

- `disconnect()`, the one sign-out both apps run, because each of its side effects acts on the developer's real data:
  - `AssetCache.shared.clear()` deletes their real cached assets;
  - `ServerAppIcons.shared.clear()`, `ServerAvatars.shared.clear()` and `ConversationAvatars.shared.clear()` drop the app icons, avatars and conversation pictures already drawn from them;
  - `ActivityFeedStore.clear()` deletes the widget's real saved feed;
  - `WidgetCenter.shared.reloadAllTimelines()` makes the real widget redraw;
  - `Keychain.clearAll()` clears their real credentials from both Keychains.
- Its storage half, `deleteAccount()`, is covered: cascade delete, memoization reset, which domains it announces, and that the device's keyboard shortcuts and appearance settings survive it, in `ConnectedAccountTests` and, for a surviving shortcut read the way a menu reads it, `ShortcutSurvivalTests`.
- `forgetCachesIfSignedOut()`, which empties the same caches again after a download a sign-out overtook, for the same reason, and because it reads the real Keychain besides.
- `persist(theming:)`, because it downloads through `AssetCache.shared` into the real App Group caches directory on every call (the logo unconditionally, even when the background is a plain colour), and its `Rainmaker.Theming` input cannot be built without linking Rainmaker.
  Its one piece of real logic is resolving a server-root-relative background against the account's address, and skipping that when `backgroundPlain` is set, `background` then holding a colour value.
  Covering it means extracting that resolution into a pure function first, at the moment [AGENTS.md → Testing](../AGENTS.md#testing) gives.
