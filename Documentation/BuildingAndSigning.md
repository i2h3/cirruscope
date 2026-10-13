<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Building and Signing

This is how the signing configuration is put together, what a build without the entitlements does on each platform, how the Mac keeps the credentials where the widget can read them, how a contributor and the CI sign, and what to check when a build fails while signing.
The rules themselves stay in [AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing): which toolchain builds, that every build signs for real, which overrides are never made, where the team is named, the Keychain flag and when to run under a base identifier of its own.
This document explains them and does not repeat them.

## Why every build carries the entitlements

The apps and the widget extension share their data through the App Group container (the store, the cached assets and the widget's last good feed) and their credentials through the Keychain access group.
A build that cannot reach them is therefore not a degraded build of the app but a broken one, which is why there is no ad-hoc configuration and no runtime fallback.

This is not theoretical.
TestFlight build 1.2.0 (50), archived by Xcode Cloud while the entitlements were set only in the gitignored `Local.xcconfig` and the tracked configuration signed ad-hoc, shipped with neither the App Group nor the Keychain access group, in the app or in the extension.
The fallbacks the code then had hid it, and had hidden it before: `1.1.0` as the App Store shipped it carries neither entitlement either.
So every `1.1.0` user's store, their keyboard shortcuts and appearance choices with it, is in the app's own container rather than the App Group's.

The reasoning and the costs accepted are in [`DECISIONS.md` → "Why must every build be signed with a real team and the App Group?"](../DECISIONS.md#why-must-every-build-be-signed-with-a-real-team-and-the-app-group).

## The store a build without the entitlements left behind

The first entitled launch moves that store across, once.
`AppDatabase.importStore(from:into:)` quarantines whatever the App Group container already holds under the store's name and moves the store and its sidecars in from the app's own container, and the migration plan then carries it forward like any other store.
Its documentation comment in `Cirruscope/Persistence/AppDatabase.swift` gives the order of the moves and the one case it resolves the wrong way on purpose.

Remove that import only once no build without the entitlement can still be on anybody's Mac.

## How the configuration chains

Each of the five targets carries its own `.xcconfig`, all of them chaining up to the root `Cirruscope.xcconfig`.
`macOS/macOS.xcconfig` and `iOS/iOS.xcconfig` include it through `Cirruscope/Cirruscope.xcconfig`, which carries the bundle identity both apps share and assigns both of them the entitlements.
`Widgets/Widgets.xcconfig`, `macOSTests/macOSTests.xcconfig` and `iOSTests/iOSTests.xcconfig` include the root directly.

- The root `Cirruscope.xcconfig` is the project's own base configuration.
  It sets the base bundle identifier and bundle name, version, deployment targets, language mode, concurrency, automatic signing with the project's development team, and the Keychain service identifier, minimum supported Nextcloud version and privacy-policy and support URLs the `Info.plist` files pass on to the code.
- It sets `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM`, the maintainer's team, above its trailing `#include? "Local.xcconfig"`, so a contributor's `Local.xcconfig` overrides it.
  The team ID is no secret, every binary signed with it carrying it.
- `CODE_SIGN_ENTITLEMENTS = Cirruscope/Cirruscope.entitlements` is assigned a level below, by `Cirruscope/Cirruscope.xcconfig` for both apps and by `Widgets/Widgets.xcconfig` for the extension, each after its include of the root.
  `Cirruscope.entitlements` declares the App Group and Keychain-sharing capabilities.
- The two test bundles, which include only the root, therefore carry no entitlements, and a root `Local.xcconfig` cannot reassign the entitlements for the three products, which is intended.
- `REGISTER_APP_GROUPS = YES` sits beside the entitlements in the same two files rather than in `project.pbxproj`.
  It is a macOS-only build setting, letting automatic signing register the App Group the entitlements name when it signs for the Mac.
- Automatic signing rejects a `PROVISIONING_PROFILE_SPECIFIER` once a team is set, which is why no target names a provisioning profile and the profile is left to automatic signing rather than named again.
- From the command line, automatic signing registers identifiers and creates or downloads profiles only when it is allowed to, which is what `-allowProvisioningUpdates` does.
  Xcode does the same on its own for the Apple ID signed in to its Accounts settings.

### Where a `Local.xcconfig` is read

The root's trailing `#include? "Local.xcconfig"` reads a `Local.xcconfig` at the repository root last, so what it sets overrides the root's own assignments, the team included.
`Cirruscope/Cirruscope.xcconfig` and every per-target `.xcconfig` end with the same `#include? "Local.xcconfig"`, resolved, like every include, relative to the file making it, as `#include "../Cirruscope.xcconfig"` shows.
So each of them also reads a `Local.xcconfig` in its own folder, such as `macOS/Local.xcconfig`, which the `.gitignore` entry ignores at any depth.
Such a file is read after its folder's own assignments, so what it sets overrides them, the entitlements included, which is why it counts among the overrides under "Nothing checks for the entitlements at build time" below.

Every folder holding one of those `.xcconfig` files is synchronized, so a `Local.xcconfig` placed in it is copied into the built product of every target listing that folder, and ignoring it in git does nothing to stop that.
That is why it is kept at the repository root.
The `.xcconfig` files themselves stay out of the products only because each is named in its folder's `membershipExceptions` in `project.pbxproj`, `Cirruscope.xcconfig` once for each app target listing `Cirruscope/`.
That is why [AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing) asks a new `.xcconfig` in a synchronized folder for an exception of its own.

## Nothing checks for the entitlements at build time

**Nothing at build time checks for the entitlements, and nothing has to.**
With the team and the entitlements in the tracked configuration, Xcode either embeds them or fails while signing.
Only a deliberate override gets around that: `CODE_SIGNING_ALLOWED=NO` or `CODE_SIGN_IDENTITY=-` on the command line or in a `Local.xcconfig`, or `CODE_SIGN_ENTITLEMENTS=` on the command line or in a `Local.xcconfig` inside a target folder.
The project supports no build made that way, an unsigned iOS compile check included.

## What a build without the entitlements does

**A build without the entitlements traps at launch, by design.**
The trap is the point: it is what a build that would otherwise show its user none of their data looks like before anyone ships it.
The documentation comments of `AppGroup.containerURL` in `Core/AppGroup.swift` and `AppDatabase.container` in `Cirruscope/Persistence/AppDatabase.swift` describe the same behaviour from the code's side.

- **iOS.**
  `AppGroup.containerURL` traps when `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` answers `nil`, which is how iOS reports a missing entitlement.
- **macOS.**
  macOS answers a URL of the expected form even for a build that is not entitled, and the App Sandbox then refuses whatever is opened under it, so there the failure surfaces in `AppDatabase.container`.
  The open fails, is retried once after quarantining the store, moving it to `.quarantine` siblings and never deleting it, and a second failure is logged as a fault and traps.
- **Caches and the feed.**
  `AssetCache` caches in the App Group's `Library/Caches/Assets` or not at all, logging a fault when that directory cannot be created, and `ActivityFeedStore` has no location but the container either.
- **The macOS widget extension.**
  It opens no store, so an unentitled build of it does not trap at all.
  It shows as `AssetCache`'s fault and `ActivityFeedStore`'s failed writes, and, being outside the apps' Keychain access group, it cannot read their credentials.

### The `ModelConfiguration` trap

**A `ModelConfiguration` naming an App Group traps rather than throwing when the build is not entitled to it.**
`ModelConfiguration(groupContainer: .identifier(…))` resolves the container inside its *initializer*, and a refused lookup is `fatalError("Unable to find App Group Container in Entitlements: …")` from `SwiftData/DataUtilities.swift`.
`containermanager` logs `client is not entitled` immediately before it.
There is no `try` to write and nothing to catch, so no amount of `do`/`catch` around the `ModelContainer` below it helps.

`AppDatabase.container` therefore resolves `AppGroup.containerURL` *before* constructing any group configuration, so that an unentitled iOS build stops at a trap whose message names the cause rather than inside SwiftData.
The store is a `static let` reached from `Store.restored()` in `iOSApp.init()`, so either trap fires at launch.

SwiftData's own trap was diagnosed only by installing such a build on a simulator and reading its log, two guesses from the crash stack alone having been wrong.

## The Keychain on the Mac

**The credentials are in the data-protection Keychain on the Mac as on iOS, which is what lets the widget extension read them.**
The reasoning and the cost accepted are in [`DECISIONS.md` → "Why are the credentials in the data-protection Keychain on the Mac as well?"](../DECISIONS.md#why-are-the-credentials-in-the-data-protection-keychain-on-the-mac-as-well).

### Two Keychains

- **The data-protection Keychain.**
  Access there is decided by the Keychain access group.
  `keychain-access-groups` names `$(AppIdentifierPrefix)$(CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER)` in both apps and the extension alike, every build being signed with the entitlements, and items are written to the default access group, the first one the entitlement names.
  On iOS it is the only Keychain, so `kSecUseDataProtectionKeychain` changes nothing there.
- **The file-based (login) Keychain.**
  It is the Mac's other Keychain, where each item carries an access control list of trusted programs and `keychain-access-groups` has no effect at all.

Releases up to and including `1.1.0` stored the credentials in the file-based Keychain.
Updating from the App Store's `1.1.0` to TestFlight build 1.2.0 (52) showed what that costs: one prompt for the app and one for `Cirruscope.app/Contents/PlugIns/Widgets.appex`.
The app creates the item, so its list names only the app.
The extension, a program of its own signed as `de.i2h3.cirruscope.widgets`, was met with a prompt, again after every sign-in because a sign-in replaced the item, while a Deny left the widget unable to read at all.
The app's own prompt was TestFlight's alone: a `1.1.0` item names the app by a designated requirement that accepts only an App Store or Developer ID signature.

### What `kSecUseDataProtectionKeychain` addresses

[AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing) has the rule that a Keychain query on the Mac never leaves the flag out.
This is what it rests on, measured in an entitled macOS process:

| `kSecUseDataProtectionKeychain` | A query searches | A deletion deletes from |
|---|---|---|
| left out | both Keychains | both Keychains |
| `false` | the file-based Keychain alone | the file-based Keychain alone |
| `true` | the data-protection Keychain alone | the data-protection Keychain alone |

A first version of the move left the flag out to mean the file-based Keychain, and so deleted the copy it had just made.
`FileBasedKeychainMoveTests` now pins the fact, so that belief cannot quietly come back.

Which queries set what:

- **`true`**
  - Every query `Core/Account/Keychain.swift` makes over the credentials in the data-protection Keychain, whether it stores, reads or enumerates them or is the first deletion `Keychain.clearAll()` makes, all of them built by `Keychain.query(_:)`.
  - The move's own two queries over the data-protection Keychain: whether that Keychain already holds a credential, and the write of each copy.
- **`false`**, the queries that address the file-based Keychain on purpose
  - `Keychain.holdsFileBasedItems(service:)`.
  - The second deletion `Keychain.clearAll()` makes.
  - Every query `Keychain.moveFileBasedItems(service:)` makes of the file-based Keychain.

### The move at launch

**The Mac app moves the file-based credentials into the data-protection Keychain at launch, and a credential it cannot move asks for a sign-in without signing out.**
The details are also in the documentation comment of `Keychain.moveFileBasedItems(service:)` in `macOS/Persistence/Keychain+FileBasedKeychain.swift`.

- `AppDelegate.applicationWillFinishLaunching(_:)` calls `Keychain.moveFileBasedItems(service:)` before window restoration, which reads credentials and runs between it and `applicationDidFinishLaunching(_:)`, and reloads the widget's timelines when anything moved.
- The move enumerates the file-based Keychain for attributes alone, that Keychain answering `errSecParam` to `kSecReturnData` together with `kSecMatchLimitAll`.
- If the data-protection Keychain already holds any credential under the service, every file-based item is deleted without being copied, whichever server it names.
  The credential there is the newer one, and copying another server's leftover beside it would leave two accounts where the app supports one.
- Otherwise the move reads each item, writes it to the data-protection Keychain, and deletes the file-based copy only once the new one is in place.
  An item that fails at any step is left for the next launch.
- Only the macOS app makes the move, being the one program the old items name.
  An App Store update reads them without a prompt, while a TestFlight build, whose signature the item's requirement does not accept, prompts during the move.
- A credential the move could not carry across, a TestFlight prompt that was denied among them, leaves the data-protection Keychain without one.
  `AppDelegate.presentInitialWindow(forLaunch:)` then finds `Keychain.holdsFileBasedItems(service:)` true and asks for a sign-in without signing out, deleting nothing, rather than finishing what would otherwise look like a sign-out that did not complete.
- The next launch tries the move again and, should it fail again, asks for a sign-in again.
  So a TestFlight build is prompted only once if that prompt is allowed, and a denied one recurs at the next launch.

### The widget until the move

Until the app has moved the credentials, `RecentActivity` asks `Keychain.holdsFileBasedItems(service:)`, which asks for attributes alone and so prompts nobody, and answers unreachable rather than no account.
The widget then draws its stale state, or its redacted placeholder where no feed was ever saved (every Mac updating from `1.1.0`, which had no widget), instead of "Not signed in".
It does so until the app's reload after the move redraws it.

### Signing out

`Keychain.clearAll()` deletes from both Keychains, so a credential not yet moved cannot sign the account back in on the next launch.
It logs an error for either deletion that fails with anything other than `errSecSuccess` or `errSecItemNotFound`.

The trade-off accepted is that the credentials no longer appear in the login keychain in Keychain Access.

## Signing as a contributor

[CONTRIBUTING.md → Code Signing](../CONTRIBUTING.md#code-signing) walks through the setup, and [`Local.xcconfig.example`](../Local.xcconfig.example) is the template.
Copy it to `Local.xcconfig` next to it, gitignored and never committed, and fill in both values, `DEVELOPMENT_TEAM` and `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER`.
The maintainer needs no `Local.xcconfig` at all.

- The identifier has to change along with the team because the shipping identifiers and `group.de.i2h3.cirruscope` are registered to the maintainer's team, and no other team can claim them.
- Every identifier the project uses derives from the base one: the apps', the extension's `.widgets`, the test bundles' `.tests`, the App Group, the Keychain service and access group, and the iOS background task.
- An Apple ID signed in to Xcode is enough.
  According to Apple's capability tables, a free Apple Developer account, without the paid membership, supports App Groups, Keychain Sharing, the App Sandbox and Background Modes on macOS and iOS alike.
- What it costs is on a physical iPhone, where a free account's provisioning profile expires after about a week.
  The Mac and the Simulator are unaffected.

A `Local.xcconfig` made from the earlier template, with Manual signing, a `PROVISIONING_PROFILE_SPECIFIER` and `CODE_SIGN_ENTITLEMENTS` at the root, must be replaced rather than kept.
With no target naming a profile of its own any more, those assignments now reach the widget extension and both test bundles as well, which signs them against a profile made for something else.

## A base identifier of its own for a run

[AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing) gives the command, with `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest`, and when to reach for it.
A contributor uses their own base identifier with `.citest` appended instead.
Automatic signing registers that identifier and its App Group under the team, so the run gets an App Group container, a store and a Keychain service and access group of its own.
The store and the Keychain start empty, and the move out of the file-based Keychain finds nothing to move.
What a test run under the shipping identifier opens instead is in [Testing → What the host apps do during a run](./Testing.md#what-the-host-apps-do-during-a-run).

## Continuous integration

**Xcode Cloud is the CI that builds and tests.**
It builds from a clean clone and signs with the tracked team and entitlements, so what it checks is the configuration that ships rather than one of its own.
Its manifest is `Cirruscope.xcodeproj/xcshareddata/xcodecloud/manifest.json`, naming the target Xcode Cloud builds and written by Xcode rather than by hand.
Building in Release, whose whole-module optimization can fail where a Debug build succeeds, is its job too.

The GitHub workflows compile nothing: `swiftformat.yml` runs on `macos-26`, which ships SwiftFormat, and the rest on `ubuntu-latest`.
So a pull request from a fork gets no automatic build or test on GitHub, and the maintainer runs Xcode Cloud on it before merging.
That is the trade-off accepted for a CI that signs like the shipping build.

## When a build fails while signing

The cause is the machine's signing setup, not the checked-in configuration, and it is fixed there, as [AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing) says.
The usual causes are:

- no Apple ID in Xcode's Accounts settings;
- an `xcodebuild` without `-allowProvisioningUpdates`;
- no `Local.xcconfig` on a machine whose Apple ID is not on the maintainer's team;
- a `Local.xcconfig` naming a team that Apple ID is not a member of;
- a `Local.xcconfig` naming a base identifier another team has registered;
- a `Local.xcconfig` still carrying the earlier template's assignments.

A build that fails before it signs, with "Cannot find type … in scope" for the `CSSearchableIndexDescription` that the `IndexedEntityQuery` conformances in `Cirruscope/AppEntities/*+Indexed.swift` name, was made with an Xcode older than 27: the SDK Xcode 26.6 ships, for one, does not have that type.
`@available` cannot help, as [AGENTS.md → Building and Signing](../AGENTS.md#building-and-signing) explains.
