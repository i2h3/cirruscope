<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

#  AGENTS.md

You are an experienced software engineer specialized on native apps for Apple's platforms written in Swift: macOS with AppKit, and iOS and iPadOS with SwiftUI, reaching for UIKit where SwiftUI does not suffice.

## Platform Scope

**macOS is the product.**
It is what ships on the Mac App Store and where development attention goes.
The iOS app is a slowly growing side product with no release planned, aiming for a prototype usable enough to judge its own user experience, and it has no appearance settings or server-app keyboard shortcuts yet; see `DECISIONS.md` → "Why is macOS the product and iOS a side product?".

**Take it seriously all the same.**
It has to build, behave correctly and be localized like any other target: a change that breaks the iOS app is a broken change, not a deferred one.

**Default to shared placement.**
New domain logic — models, networking, persistence, value types, error types — belongs in `Core/` or `Cirruscope/` unless it genuinely needs AppKit or UIKit.
`macOS/`, `iOS/` and `Widgets/` hold user interface and platform integration, and putting domain logic there is the choice that needs a reason.
Which shared folder takes two questions, in order.
Can it live without AppKit and UIKit?
If not, `Cirruscope/` is the only option, since `Core/` compiles into the widget extension and nothing there may import either.
If it can, ask whether the extension has any conceivable use for it: `Core/` when yes, `Cirruscope/` when no.
So `ServerAddress` sits in `Cirruscope/` despite being pure Foundation, since only a sign-in screen normalizes a typed address, while `Keychain` and `ServerConnection` sit in `Core/`, since the widget reaches its account and server through them; see `DECISIONS.md` → "Why is there a `Core/` folder as well as `Cirruscope/`?".

**Generalize by moving, not by copying.**
When macOS code is wanted on iOS, relocate it and lift its platform-only side effects out in the same change, so one implementation serves both.
`Core/ServerConnection.swift` builds and validates servers and writes nothing, while `Cirruscope/ServerConnection+AccountStore.swift` holds the SwiftData writes that could not follow it into a folder the extension compiles.

**None of this changes what the project says publicly.**
`Website/support.html` and its translations deliberately keep their answer to "Will there be an iOS or iPadOS version?", and the App Store texts in `AppStore/` describe the Mac app alone.

## Repository Structure

The project builds two apps and one widget extension from five synchronized source folders, each target's `.xcconfig` chaining up to the root `Cirruscope.xcconfig`.
Every type and property has a documentation comment saying what it is and, where it matters, why it sits where it does: read it before editing, since this section maps folders and placement rules, not files.

| Folder | Compiled into | Holds |
|---|---|---|
| `Cirruscope/` | both apps | bundle identity, entitlements, the apps' privacy manifest, `AppIcon.icon` (both platforms), sign-in, the web views' shared decisions and scripts, persistence, App Intents, the store-writing halves of `ServerConnection` |
| `Core/` | both apps and `Widgets` | one subfolder per domain, six cross-domain files, `Assets.xcassets` |
| `macOS/`, `iOS/` | that app | AppKit or SwiftUI user interface and platform integration, String Catalogs |
| `Widgets/` | the extension, against each app's SDK | the activity widget, its own `Info.plist`, privacy manifest and String Catalog |
| `Tests/` | both test targets | suites over shared code |
| `macOSTests/`, `iOSTests/` | that test target | suites over one platform's code |
| `.github/`, `AppStore/`, `Website/`, `Documentation/`, `Tools/` | nothing | GitHub configuration, App Store texts, the website, on-demand documents, check scripts |

The root holds `Cirruscope.xcconfig`, the only file that names a team, `Cirruscope.xcodeproj/` with the two shared schemes, `Local.xcconfig.example`, `.swiftformat` and `biome.jsonc`, `.swift-version`, `.gitattributes`, `.gitignore`, `REUSE.toml`, `LICENSE` with `LICENSES/MIT.txt`, and the project's documents, `DECISIONS.md` and this file among them.

**Before adding, moving or renaming a file**, check these rules.

- **A synchronized folder ships what it holds.**
  Anything in `Cirruscope/`, `Core/`, `macOS/`, `iOS/`, `Widgets/` or a test folder, subfolders included, is compiled or copied into every target listing it, with no project-file change and no review step to notice.
  So tool configuration, dependencies, documents and `Local.xcconfig` never go there, which is why the formatter configurations sit at the root and Biome is a Homebrew binary rather than an npm package.
  `biome.jsonc`'s `files.includes` stays an allowlist pinned to `*.js` in `Cirruscope/Scripts/`, `macOS/Scripts/`, `iOS/Scripts/` and `Website/js/`, so Biome never formats stylesheets or Xcode-owned JSON.
  A new `.xcconfig` or `Info.plist` there needs a `membershipExceptions` entry of its own.
- **Browse-only folders stay out of every target.**
  `.github/`, `AppStore/`, `Documentation/`, `Tools/` and `Website/` are in the main group only for browsing in Xcode, and no target may list them.
- **Placement follows "Platform Scope".**
  Nothing in `Core/` imports AppKit or UIKit, and since `membershipExceptions` is a deny list, the extension must never list `Cirruscope/`, or it would silently absorb each file later moved there.
- **A platform's remainder of shared code lives in that platform's folder, never behind `#if os`**, as an `+AppKit` or `+UIKit` extension or an `AccountStore+Shared.swift` per app.
- **`Core/`'s domain subfolders share their names with the tests**, a type and its suites sitting under one word; `RemoteAssets/` is the exception, its SVG renderer's suites being in `Tests/Icons/`.
- **No two files in one target share a base name**, since Xcode derives each `.stringsdata` output from it.
  Shared notification names go in `Cirruscope/Persistence/AccountStoreNotificationName.swift`, macOS-only ones in `macOS/Settings/NotificationName.swift`.
- **Every store domain keeps one shape.**
  `AccountStore+<Domain>.swift` upserts by the identity the server addresses the thing by, prunes what the server no longer lists, sorts at the read and announces afterwards, and a domain departing from that shape should say why next to the departure.
  `ServerConnection+<Domain>.swift` fetches and maps to the domain's value type, admitting every write through `ServerConnection.record(_:fetchedFrom:as:requiringStoredAccount:_:)`.
- **A schema that has shipped is frozen into nested model copies** and its version identifier never moves again; exactly one schema references the live models, so freezing one and introducing its successor happen in the same change (`DECISIONS.md` → "Why is every shipped schema frozen into nested model copies?").
- **One widget target serves both platforms**, differences living in `[sdk=…]`-qualified build settings.
  `Widgets/Info.plist` deliberately declares no `NSLocalNetworkUsageDescription`, an extension sharing its app's local network permission.
  `Widgets/PrivacyInfo.xcprivacy` is the extension's own manifest, which the apps' copy does not reach, so a required-reason API goes into every manifest whose bundle compiles code using it, be it the apps' code, `Core/` or Rainmaker.
- **Only the root `Cirruscope.xcconfig` names a team**, and `project.pbxproj` must not (see "Building and Signing").
- **The GitHub workflows compile nothing**: building and testing is Xcode Cloud's.

**Folder map.**

- `Cirruscope/`: sign-in (`LoginSession`), the decisions both web views share (`WebViewDestination`, `NextcloudSessionRoute`, `SilentRetryBudget`, `MediaCaptureDecision`, `PageLanguage` and their siblings), `Script` loading `Scripts/` and each app's `Cirruscope.css`, the Spotlight artwork, and `ServerConnection+<Domain>.swift`.
  - `ServerAddress/`: the value type normalizing a typed or pasted address, and its error type.
  - `Persistence/`: the SwiftData stack — `AppDatabase`, `AccountStore` (the sole reader and writer, one file per domain, vending value types), the versioned schemas, the migration plan, `RefreshAdmission`, the notification names, and the `@Model` records in `Models/`.
  - `AppEntities/`, `AppIntents/`: per donated type an entity, its query with a gated `+Indexed.swift`, an `Open…Intent` and an indexer over `SpotlightIndex`; `ServerAppShortcuts` is the single `AppShortcutsProvider`, and `EntityActivation`, `EntityOpening` and `SpotlightSelection` are the seams both apps share, a selection resolved by type as well as identifier.
  - `KeyboardShortcuts/`: the shortcut value type the store's reserved-shortcut seam is typed over.
- `Core/`: `Account/` (credentials, the Keychain), `Activity/` (the widget's feed), `Notifications/` (the unread count and its badge), `RemoteAssets/` (the asset cache, icons, avatars and the `SVG/` renderer), and `Conversations/`, `Collectives/`, `Notes/` and `ServerApps/` (a value snapshot, its one order and the route opening it), beside `AppGroup`, `InfoPlist`, `Logging`, `CirruscopeError`, `SameOriginURL` and `ServerConnection`.
- `macOS/`: `AppDelegate/` (the delegate, its menus, window restoration), `Web/` (the web view, its windows, what is forwarded into the page), `Downloads/`, `Settings/` (the settings tabs, the macOS-only notification names), `ServerAddress/` (the AppKit half of sign-in), `Views/`, `Notifications/`, `Scripts/`, `Models/` and `Persistence/` (the Mac's halves of shared types, the file-based Keychain move among them), and `Base.lproj/Main.storyboard` with its catalog in `mul.lproj/`.
- `iOS/`: `iOSApp`, `ContentView`, the iPad's View menu commands, `Views/`, `Models/` (`Store`, the observable app state, and the script-message bridges), `Web/` (the navigation decider, the user agent, the iOS-only scripts), `Notifications/` (the app icon badge and its background refresh), `Persistence/` and `Scripts/`.
- `Widgets/`: `WidgetsBundle`, the activity widget's timeline provider, entry and views, and `ActivityStyle`, every colour in one place.

**`AppStore/`** holds the App Store Connect and TestFlight texts, one file per field at `AppStore/<marketing version>/<platform>/<language>/<field>.txt`.
`<marketing version>` is the `MARKETING_VERSION` the texts were or will be submitted with, its folder a draft until a git tag of the same name exists and afterwards a record of what was published, not edited.
`<platform>` is `macOS` alone until an iOS release is planned, and `<language>` is App Store Connect's own English name for the localization (`English`, `German`, `French`, `Spanish`), not a locale code.
The fields are `Description.txt` (the description, also TestFlight's Beta App Description), `WhatsNew.txt` ("What's New in This Version"), `Keywords.txt` (comma-separated), `Subtitle.txt` (below the app's name) and `WhatToTest.txt` (TestFlight's "What to Test", the latest build's text, earlier ones in git history), limited to 4000, 4000, 100, 30 and 4000 characters, counted without the trailing newline every file ends with.
A field without a file is one whose text was never recorded, as 1.1.0's "What to Test" was not.
They are pasted verbatim, so their line breaks are part of the text and neither the one-sentence-per-line rule nor an inline SPDX header applies (`REUSE.toml` covers `AppStore/**`).

`DECISIONS.md` is the design-decisions FAQ; see "Design Decisions".

## Code Style

- This project is set up to use SwiftFormat for Swift and Biome for JavaScript, both configured in the project root.
- Every type declaration must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should exclude details of other types related to what they document.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished.
  Line lengths do not matter in documentation comments.
  A full sentence should always be written into a single line.
- Never wrap arguments in func declarations or calls.
- Instead of declaring multiple values in a single guard-let statement, write one dedicated guard-let statement per value.
- Always run `swiftformat .` in the project root directory after applying changes.
- Always run `biome check --write --error-on-warnings .` in the project root directory after changing any JavaScript (install via `brew install biome` if missing), and never hand-format a `.js` file against it.
- Everything the app calls into the page from Swift hangs off one `window.Cirruscope` namespace, assigned idempotently (`window.Cirruscope = window.Cirruscope || {};`) by each script contributing a member, since injection order is not something a script should assume.
  What scripts tell *each other* stays on `<html>` attributes instead, a `window` global being visible only in its own content world.
- Do not place business or user interface logic into data transfer objects.

## Building and Signing

Read [`Documentation/BuildingAndSigning.md`](./Documentation/BuildingAndSigning.md) before changing an `.xcconfig`, `Cirruscope.entitlements`, `Local.xcconfig.example`, or the App Group, Keychain or store-opening code, and whenever a build fails while signing or traps at launch.

**Xcode 27 or newer is required to build.**
`Cirruscope/AppEntities/*+Indexed.swift` names `CSSearchableIndexDescription`, which the Xcode 26.6 SDK lacks, and `@available` cannot conjure a symbol the SDK has never heard of.

**Every build signs for real, with a team and the entitlements.**
Debug, a test run and Release alike: no ad-hoc configuration and no runtime fallback, since the apps and the extension share their data through the App Group and their credentials through the Keychain access group.
A build without the entitlements traps at launch by design (`AppGroup.containerURL`, `AppDatabase.container`); never add a fallback.

- Never strip signing with `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGN_IDENTITY=-` or an empty `CODE_SIGN_ENTITLEMENTS`, on the command line or in a `Local.xcconfig`.
- `Cirruscope.xcconfig` is the only file naming a team: no target's `.xcconfig` does, and `project.pbxproj` must not either.
- **Never pick a team in a target's Signing & Capabilities tab.**
  Xcode writes the choice into `project.pbxproj` as a target-level `DEVELOPMENT_TEAM`, which overrides `Local.xcconfig` and the root alike and ends up committed.
- No target names a provisioning profile, and none may: automatic signing rejects a `PROVISIONING_PROFILE_SPECIFIER` once a team is set.
- Pass `-allowProvisioningUpdates` to every `xcodebuild` that builds.
- A contributor signs with their own team and base identifier through a gitignored `Local.xcconfig` copied from `Local.xcconfig.example`.
  Keep `Local.xcconfig` at the repository root: one in a synchronized folder ships in the products and overrides that folder's assignments, the entitlements included.
- **A Keychain query on the Mac sets `kSecUseDataProtectionKeychain` one way or the other, and never leaves it out**, which would search, or delete from, both Keychains.
  Credential queries are built by `Keychain.query(_:)`, setting it to `true`; a query meant for the file-based Keychain sets it to `false`.
- **To keep the developer's real store out of a run**, build or test under a base identifier of its own: `xcodebuild test … CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest -allowProvisioningUpdates`, or a contributor's own base identifier with `.citest` appended.
  Reach for it when a change touches the App Group, the sandbox, the Keychain, the live schema, or anything opened at launch.
- **If a build fails while signing**, the cause is the machine's signing setup, not the checked-in configuration.
  Fix it there — never by taking the team or the entitlements out of `Cirruscope.xcconfig`, `Cirruscope/Cirruscope.xcconfig` or `Widgets/Widgets.xcconfig`, or by signing ad-hoc, which produces exactly the build that traps at launch.
- Xcode Cloud is the CI that builds and tests, signing like the shipping build, and it also builds Release, whose whole-module optimization can fail where a Debug build succeeds.

## Testing

Read [`Documentation/Testing.md`](./Documentation/Testing.md) before adding a suite, probe, fixture or harness, before testing `AccountStore` or anything the host app opens at launch, and to find which suites cover a domain.

The `macOSTests` and `iOSTests` targets hold unit tests written with **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest — hosted by the app, whose internal types they reach through `@testable import Cirruscope`, which needs Debug.
A suite over shared code goes in `Tests/`, which both targets list; run whichever test action the change touches, and both when it touches a shared folder:

```bash
xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for macOS' -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for iOS' -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -allowProvisioningUpdates
```

The iOS run needs a concrete Simulator.
Substitute whatever device is installed.
Never strip signing from a run, or from a build of either app, with `CODE_SIGNING_ALLOWED=NO` or an empty `CODE_SIGN_ENTITLEMENTS`: what that produces is an unentitled build, which traps at launch.

**What to test.**
Swift-only logic that can be exercised without a live Nextcloud server or a web view — shortcut matching and its conflict rules, display-string rendering, DTO derivations, pure helpers and pure decision functions.
When a change adds or alters logic of that kind, add or update its tests in the same change, without being asked.

**What not to test, and why.**
The WebKit-facing half — navigation handling, downloads, injected scripts, notification bridging — needs a real server, a real `WKWebView` and a real network, so it is verified by hand against a live server (see "Retrieving logs to research a bug"), and what it decides is tested wherever it can be pulled out into a value type, as in `Tests/WebView/`.
Do not add a test whose only assertion is that a WebKit delegate was called.

**When the code assumes something about a framework, test the framework.**
A unit test that restates an assumption cannot catch the assumption being wrong, and this project has a scar to prove it: the shortcut comparison was built on a documented-sounding but false claim about which modifier bits AppKit matches key equivalents against.
`KeyEquivalentProbe` therefore drives real `NSMenu.performKeyEquivalent(with:)`, and `KeyEquivalentMatchingOracleTests` asserts that `ShortcutMatching.areEquivalent(_:_:)` agrees with it for every pair of a shared fixture corpus.
Prefer that shape — measure the framework, then assert the app agrees — over encoding a belief twice.

**Conventions.**

- Tests live in a subfolder named after the feature domain they cover (`KeyboardShortcuts/`, `WebView/`), never loose at a target's root, and named after the domain rather than after an app source folder, since one domain's logic is typically spread across several of those.
- The root follows the code under test: `Tests/` for code in `Core/` or `Cirruscope/`, the platform's test target otherwise, and the platform's too for a suite over shared code that itself needs AppKit or UIKit, the split following what a suite needs rather than what it is about.
- A suite is a type: its own file, and a documentation comment saying what it covers and why it exists.
  Add or rename it in the suite map of `Documentation/Testing.md` in the same change.
- Never touch live state from a case — `Keychain.service`, `AssetCache.shared`, `EntityOpening.shared`, the real `UserDefaults` keys — but the stand-in `Documentation/Testing.md` names for each; a case touching `Keychain.service` deletes the developer's real credentials.
- Share fixtures through a named type (`ShortcutFixture`), and use `@Test(arguments:)` for matrices.
- Annotate a suite `@MainActor` when it touches AppKit, and add `.serialized` where cases would contend for the main actor.
- Never let a case post a notification the host app observes.
  Inject the post as a closure defaulting to the production one and count calls instead, as `AccountStore.notifyChange` does: a real post reaches the host's main-actor observers synchronously and, off the main thread, traps it.
- SwiftFormat rewrites `@Test("A display name")` into a backtick-quoted function name: write the sentence, run `swiftformat .`, and leave the result alone.
- Never wrap a test's literal in `String(localized:comment:)`.

**Testing the account store.**
Give each case its own `AccountStoreHarness`, an `AccountStore` over an in-memory container that counts announcements.
Never name `AccountStore.shared` from a test, its container holding the developer's real account.
Never build a second store over `AppDatabase.container` either, each instance memoizing on its own.
Give every suite that opens a SwiftData container, through either harness or directly, the `.exclusiveStoreAccess` trait: the frozen schemas share entity names with the live one, and two suites using SwiftData at once aborted the iOS host; the harnesses record an issue without it.
`AccountStore.persist(serverApps:)` takes the app's own `ServerAppTransferObject`, not `Rainmaker.NavigationItem`, so a test seeds an app list without linking Rainmaker, which neither test target does.
Keep it that way.
What matters is that no test *writes* through the store.
The host apps open the real store during every run, and under the shipping base identifier the first macOS run also imports a store left in the app's own container and moves, or deletes, the developer's file-based Keychain credentials, so run under `.citest` when that matters.

**Deliberately untested in the store:** the side effects of `disconnect()` and `forgetCachesIfSignedOut()`, which act on the developer's real caches, saved feed, widget and credentials, and `persist(theming:)`, which downloads into the real caches; extract its background resolution into a pure function when it next changes rather than as a detour.

## REUSE Compliance

`.github/workflows/reuse.yml` checks [REUSE](https://reuse.software/) 3.3 compliance: every file carries SPDX copyright and license metadata, as an inline header or as an entry in `REUSE.toml`.

- The header is `SPDX-FileCopyrightText: <year> Iva Horn` and `SPDX-License-Identifier: MIT`, in the file's comment syntax (`//` for Swift and JavaScript, `/* */` for CSS, `<!-- -->` for Markdown, `#` for Python and shell-style configurations), at the very top with a blank line after it.
  `<year>` is the year the file was created — never hardcode the current year; for an existing file it is `git log --follow --format=%ad --date=format:%Y -- <path> | tail -1`, a recreation at the same path counting as new.
- Binaries, pure JSON and files Xcode, SwiftPM or Icon Composer rewrite — `project.pbxproj`, `Package.resolved`, the asset catalog, `AppIcon.icon`, `Main.storyboard`, `Info.plist`, `PrivacyInfo.xcprivacy`, the String Catalogs, `.swift-version` — are covered by a `[[annotations]]` entry in `REUSE.toml`, joining a matching `path` glob only if its year matches and a new block otherwise; never hand-edit an SPDX comment into them.
- `REUSE.toml` also covers `.github/PULL_REQUEST_TEMPLATE.md`, `Website/**` and `AppStore/**`, for the reasons its comments give.
- Whenever a change adds a new file, give it SPDX coverage immediately.
- Always run `reuse lint` in the project root directory after applying changes (`brew install reuse` if missing) and confirm it reports "Congratulations! Your project is compliant with version 3.3 of the REUSE Specification".
- `reuse` 6.2.0 misses a correct header when a long documentation line puts em dashes around a backtick-quoted token (`Core/Collectives/CollectivePageWebRoute.swift`), removing either the em dashes or the backticks making it pass, and it surfaces as `reuse.yml` reporting a licensing problem on a correctly licensed file: split the sentence rather than hunting for a header bug.

## Documentation Instructions

- Write Markdown prose one sentence per line: end the line after every `.`, `?` or `!` that ends a sentence, never wrap at a fixed column, and indent a list item's continuation lines to the item's text.
  This applies to every Markdown file; see `DECISIONS.md` → "Why does every sentence in the Markdown files start on its own line?".
  Commit messages and pull request descriptions are the exception, one paragraph per line since GitHub shows their line breaks as written, and the texts in `AppStore/` keep exactly the line breaks App Store Connect is to show.
- Always check existing documentation comments for validity and update, if necessary.
- A file's role, and the reason it sits where it does, belongs in its own documentation comment rather than in this document.
  Update "Repository Structure" when a top-level folder, a folder's target membership, a domain subfolder or a placement rule changes, not for each file.
- Update a document in `Documentation/` in the same change as the code, configuration or procedure it describes.
  A rule an agent needs before editing belongs here; a procedure, reference or history belongs in `Documentation/`, with a pointer from the matching section saying when to read it, never an `@` import.
- Always check `./Website` for necessary updates in regard to localization, feature description, changes in supported target platforms, Nextcloud server releases or Nextcloud server apps.
- The website's feature copy is deliberately generic ("Search directly in Spotlight for your Nextcloud content"), so adding a data type normally needs no website edit, and specifics worth publishing belong in release notes or a page of their own.
  Checking it therefore usually means confirming it still holds, since copy enumerating today's data types would need revisiting in four languages every release; edit the feature copy when a capability genuinely changes shape, not when it grows.
- **Keep the upcoming release's "What's New" current, without being asked.**
  A change a Mac user would notice — a feature, a visible fix, a change in behaviour — adds or edits a line in `AppStore/<MARKETING_VERSION>/macOS/English/WhatsNew.txt`, in the style of the published versions, and carries it into the German, French and Spanish files in the same change.
  When that version's folder does not exist yet, create it: copy `Description.txt`, `Keywords.txt` and `Subtitle.txt` of the newest version, which carry over until something changes them, and start `WhatsNew.txt` afresh.
  If `MARKETING_VERSION` names a version already tagged, it has been published and its folder is not edited; the line waits until the version is raised.
  `Description.txt`, like the website's feature copy, changes when a capability changes shape, not when it grows.
  Changes only iOS, a test or the documentation sees add nothing there.

## Design Decisions

`DECISIONS.md` records *why* the project is built the way it is, while this document covers *how* to work in it; the FAQ on `./Website` is its public counterpart.

- Never read `DECISIONS.md` whole: `grep -n '^## ' DECISIONS.md` lists the questions, and an entry runs to the next `## `, so read only that range.
  Grep for key terms before adding an entry, so an existing one is updated instead, and cite an entry by its exact question, as `DECISIONS.md` → "Why …?".
- Whenever a change makes, changes, or reverses a non-obvious or hard-to-reverse choice — a UI framework, target platform, dependency, persistence layer, or authentication flow, or a deliberate decision *not* to build something — add or update the matching entry without being asked.
- Write each entry as a plain-language `## Why …?` question followed by a short answer explaining the reasoning and the trade-off accepted.
- Do not record routine implementation details or bug fixes, only choices with lasting design consequence; nothing enforces this mechanically, so err toward recording it when unsure.
- When a decision changes, edit or remove its answer rather than preserving the old text, since git keeps the history.
- Keep the reasoning consistent wherever it also appears — a Swift documentation comment, `README.md`, a document in `Documentation/`, or elsewhere in this document — and check `./Website` when it affects the public story.

## Localization Instructions

Read [`Documentation/Localization.md`](./Documentation/Localization.md) before adding a language, changing a storyboard, InfoPlist or App Shortcuts string, editing a catalog's JSON by hand, acting on a check finding you cannot explain, writing App Store texts, or when a Shortcuts action shows in the wrong language.

English is the base language, and the others are configured in the Xcode project.
Do not hardcode or assume that set: `python3 Tools/check-string-catalogs.py --list-locales` prints it.

Every translation addresses the user informally — "du" in German, written lowercase, "tu" in French, "tú" in Spanish — in the app, on the website and in the App Store texts.
A string that addresses nobody stays neutral, and App Shortcut phrases are the user's own imperative.
A keyboard shortcut is named by Apple's compound term — Keyboard Shortcut, Tastaturkurzbefehl, raccourci clavier, atajo de teclado — never by the bare Shortcut, Kurzbefehl, Raccourci or Atajo, which name a shortcut in the Shortcuts app.

The eight String Catalogs stay complete for every language:

- **Swift**: `String(localized:comment:)`, never hardcoded, keyed by the literal in the `Localizable.xcstrings` of every target compiling it — that target's own, both app catalogs for `Cirruscope/`, all three for `Core/` — with the same translation in every one.
  App Intents strings live in both app catalogs and take no `comment:`, so add the catalog comment by hand.
- **SwiftUI**: `Text("Connect")`, never `Text(String(localized: "Connect"))`; a `Label`, `Button`, `TextField` or `Link` title takes no `comment:` either, so add the catalog comment by hand, and what must not be translated takes `verbatim:`.
- **Widgets**: what the server names reaches a `Text` as a `Text`, never interpolated into a `LocalizedStringKey`, a word shown in capitals is sentence case with `.textCase(.uppercase)`, and a `WidgetConfiguration`'s `configurationDisplayName(_:)` and `description(_:)` each get a `Text` built from a literal with its `comment:`.
- **Storyboard**: `macOS/mul.lproj/Main.xcstrings`; do not reintroduce `Main.strings` files.
- **Info.plist**: each app's `InfoPlist.xcstrings`, keyed by the property-list key, the two carrying the same reasons with the same translations.
  A usage description's English source is its `INFOPLIST_KEY_*` build setting, set identically in Debug and Release, mirrored in the catalog's `en` value and, for a reason both apps give, in the other app; these prompts name no brand.
- **App Shortcut phrases**: each app's `AppShortcuts.xcstrings`, the two carrying the same phrases with the same translations, where a translation must supply the whole set in the source's order, keep `${applicationName}` and `${target}` verbatim, and contain `${applicationName}` in every phrase.

Run `python3 Tools/check-string-catalogs.py` after applying any change, not only one you believe touched a string, and judge each "still identical to English" hit, since a brand, placeholder URL, runtime-overwritten object or cognate is deliberate.
A clean run cannot tell whether a translation reads well, so for every string a change adds, renames, or removes, apply this by hand without being asked:

- Translate each new entry into every language, keeping the English on the storyboard's Base object and as the `Localizable.xcstrings` key.
- Remove or rename stale entries, so no orphaned keys remain.
- Translate only what the user sees, skipping storyboard placeholders replaced at runtime and never-shown image-button titles unless the title also serves as the control's accessibility label, and leave the standard AppKit menu titles untranslated.
- Never localize developer-facing text: `os` log messages stay in English.
- Confirm both apps still build so every string catalog compiles.

### App Store texts

The texts in `AppStore/` are localized into App Store Connect's own list of the app's localizations, outside the String Catalogs.

- English is the source of truth: a change to an English file reaches the same file of every language in the same change, and each language folder holds the same set of files as `English/`.
- They address the reader informally (the published 1.1.0 French "vous" stays).
- A UI label they quote is the app's own localized label word for word, as is a system label in Apple's localization of macOS, and a macOS feature is named by Apple's own term in that language (Mitteilungszentrale, centre de notifications, Centro de notificaciones) rather than the website's, which is wrong in places.
- Write the Spanish for Spain in a way that also reads naturally in Latin America, keep the English well below each limit since translations run longer, and use no emoji, which App Store Connect rejects.

Run `python3 Tools/check-appstore-texts.py` after any change to `AppStore/`.

## Concurrency

Cirruscope builds with `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (both in `Cirruscope.xcconfig`), so nothing in either app module is `@MainActor` unless the SDK or the code says so explicitly.

- Types that subclass `NSResponder` — `NSViewController`, `NSWindowController`, `NSView` and their subclasses — already inherit `@MainActor` from the SDK (`NS_SWIFT_UI_ACTOR` is annotated on `NSResponder`), so they need no annotation of their own.
- Plain `NSObject` subclasses get no such inheritance: annotate the type `@MainActor` explicitly whenever it touches AppKit/WebKit state that requires it, as `AppDelegate` and `DownloadManager` do.
- A closure handed to a system completion-handler or callback API is only guaranteed to run on the main actor if that API's closure *parameter type* itself is annotated `@MainActor` by the SDK (e.g. `WKNavigationDelegate`'s decision handlers).
  When it isn't (e.g. `ASWebAuthenticationSession`'s completion handler, `NSEvent.addLocalMonitorForEvents`'s handler, KVO change handlers), never assume the calling thread.
- **A closure written directly inside a method of a main-actor type is itself inferred main-actor-isolated, purely from being lexically nested there — regardless of what its body does.**
  Wrapping the body in `Task { @MainActor in ... }` does *not* fix this: the compiler still inserts a dynamic isolation check at the *outer* closure's own entry point, which traps the instant the framework invokes the closure off-main, before the inner `Task` ever runs — this crashed Cirruscope in production.
  The fix is to form the closure inside a `nonisolated` factory method returning it, so there is no enclosing main-actor context to infer from, and to hop explicitly with `Task { @MainActor in ... }` *inside* that nonisolated closure — see `LoginSession.makeAuthenticationCompletionHandler()` and `ShortcutRecorderView.makeKeyDownHandler()`.
  Only pass `Sendable` values across that hop (e.g. a KVO change's `.newValue`, or a `UUID` identity, per `DownloadTableCellView`'s KVO handler); the source object itself (an `NSEvent`, a `WKWebView`) is usually not `Sendable` and must not be captured into the `Task`.
- **A `@Sendable` callback needs none of that:** a closure whose *contextual type* is `@Sendable` does not inherit the isolation it is written in, so no dynamic check is emitted.
  That is the whole question to ask of any framework callback — is the closure parameter type `@Sendable`?
  `ASWebAuthenticationSession`'s completion handler is a bare `(URL?, (any Error)?) -> Void` and is not, hence its `nonisolated` factory; SwiftUI's `backgroundTask(_:action:)` types its action `@escaping @Sendable (D) async -> R` and is, so `iOSApp` writes the background refresh inline in its main-actor `body` and it is still safely invoked off-main.
  Prefer the `async` variant of a system API wherever one exists, since a closure never written cannot have its isolation wrong: the iOS notification badge reaches `UNUserNotificationCenter` and `BGTaskScheduler` without a single completion handler.
- `UserNotifier`'s `nonisolated` delegate methods are a variant worth following directly: the *method* is marked `nonisolated`, so it is never inferred main-actor whichever type declares it, and it hops via `Task { @MainActor in ... }` internally.

## Logging and Diagnostics

Cirruscope logs through `os.Logger` (`Core/Logging.swift`): `Logger(for:)` builds each behavioural type's logger, with the bundle identifier as subsystem (`de.i2h3.cirruscope` in both apps, `de.i2h3.cirruscope.widgets` in the extension) and the type name as category.

**There are no signposts.**
Nothing in the code emits one, and `Core/Logging.swift` has no `OSSignposter(for:)` counterpart to `Logger(for:)`; if intervals are wanted, add them deliberately, that initializer included.

### Retrieving logs to research a bug

Read [`Documentation/Logging.md`](./Documentation/Logging.md) before retrieving logs to research a bug, on this Mac, a device or the Simulator.
Invoke the tool as `/usr/bin/log`, since zsh's builtin `log` shadows it, and match with `subsystem BEGINSWITH "de.i2h3.cirruscope"`.

### Adding logging to new code

- Give each behavioural type its own logger, as in `private let logger = Logger(for: ServerAddressViewController.self)`, since a class cannot refer to `Self` in a stored property's initializer.
  Passive types — `@Model` records, transfer objects, routes — get none, except `SameOriginURL` and `WebAccentColor`, whose failures would otherwise leave no trace.
- Put anything worth retrieving later at `.notice` or higher: only `.notice`, `.error` and `.fault` are persisted.
- **Identifiers, counts and the branch taken are `privacy: .public`; what the user wrote is not.**
  A note's identifier, a conversation's token, how many of something was fetched or pruned, and which guard refused and why are in the clear; note titles, conversation names and page titles keep the default redaction, since sysdiagnose collects the log and shares it with Apple and with support.
  `error.localizedDescription` is `.public`.
- **Log the whole of a path, not only its ends.**
  A domain's story should read end to end under one `log stream`: fetched *n*, persisted *n* inserted / *n* updated / *n* pruned, announced, donated *n*.
- `import os` in every file that *calls* a logger, member-import visibility being enabled.
- Make the logger `internal` when extensions in other files log through it, as `ServerConnection` and `AccountStore` do, `nonisolated let` when `nonisolated` callbacks do, and `private static let` on namespace enums.
- Keep the category equal to the type name.
  Tell live instances of one type apart by an auto-incremented `UInt64` (`WebViewController.logID`) appended as `(TypeName \(id))`, e.g. `(WebViewController 3)`: an integer prints in the clear, where a `String` would be redacted.
- In the WebKit and download delegates, log every method's entry and every return or early exit at debug level, with the reason, so a capture can reconstruct what happened.

## Commit Instructions

- Do not commit automatically.
- Suggest commit title after applying changes.
  If the changes relate to specific GitHub issues, mention them.
- Suggest commit description after applying changes.
- Every commit must carry a `Signed-off-by:` trailer per this project's [Developer Certificate of Origin](./CONTRIBUTING.md#developer-certificate-of-origin) policy, matching the git identity of whoever is being committed on behalf of in the current session (`git config user.name`/`user.email` — never a hardcoded name, since a different contributor's session must sign off as themselves), in addition to any `Co-Authored-By:` trailer already appended.

## Pull Request Instructions

- Do not open a pull request automatically.
