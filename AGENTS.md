<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

#  AGENTS.md

You are an experienced software engineer specialized on native apps for Apple's platforms written in Swift: macOS with AppKit, and iOS and iPadOS with SwiftUI, reaching for UIKit where SwiftUI does not suffice.

## Platform Scope

**macOS is the product.**
It is what ships on the Mac App Store and where development attention goes.
The iOS app is a real but slowly growing side product, worked on now and then rather than driven to a date: no release is planned or scheduled, and the near-term goal is a prototype usable enough to judge its own usability and user experience.

**Take it seriously all the same.**
It has to build, its behaviour has to be correct, and its user-facing strings are localized like any other target's.
It is not a placeholder that may be left broken while macOS moves — a change that breaks the iOS app is a broken change, not a deferred one.

**Default to shared placement.**
New domain logic — models, networking, persistence, value types, error types — belongs in `Core/` or `Cirruscope/` unless it genuinely needs AppKit or UIKit.
`macOS/`, `iOS/`, and `Widgets/` hold user interface and platform integration.
Putting domain logic in a platform folder is the choice that needs a reason, not the default that needs none.
Which of the two shared folders takes two questions, in order.
Can it live without AppKit and UIKit?
If not, `Cirruscope/` is the only option — `Core/` compiles into the widget extension and nothing there may import either.
If it can, ask whether the extension has any conceivable use for it: `Core/` when yes, `Cirruscope/` when no.
That second question is not pedantry — it is why `ServerAddress` sits in `Cirruscope/` despite being pure Foundation, since only a sign-in screen normalizes an address somebody typed, and it is why `Keychain` and `ServerConnection` sit in `Core/`, since the activity widget finds its account and reaches its server through exactly those.
See `DECISIONS.md` → "Why is there a `Core/` folder as well as `Cirruscope/`?".

**Generalize by moving, not by copying.**
When macOS code turns out to be wanted on iOS, relocate it and lift the platform-only side effects out of it in the same change, so one implementation serves both rather than two drifting ones.
The worked example is in the tree: `Core/ServerConnection.swift` builds and validates servers and writes nothing, while `Cirruscope/ServerConnection+AccountStore.swift` holds the SwiftData writes that could not follow it into a folder the app extension also compiles.

**None of this changes what the project says publicly.**
`Website/support.html` — and its `de/`, `es/`, and `fr/` translations — still answer "Will there be an iOS or iPadOS version?" as they do today, and that answer is deliberately not revised to match this section.
The App Store texts in `AppStore/` likewise describe the Mac app alone.
This is how the work is organized, not what has been promised.

## Repository Structure

The project builds two apps and one widget extension from five source folders.
Two of them are shared: `Cirruscope/` holds what both apps share and the extension does not, from their bundle identity and configuration to sign-in, the decisions both web views make, persistence and App Intents; `Core/` holds the code and assets every target shares, including the extension.
The other three — `macOS/`, `iOS/`, and `Widgets/` — hold what each target needs alone.
Each of the five targets carries its own `.xcconfig`, all of them chaining up to the root `Cirruscope.xcconfig`.

- `Cirruscope.xcconfig` is the root build configuration: the project's own base configuration, and the file every target's own `.xcconfig` includes, directly or through `Cirruscope/Cirruscope.xcconfig`.
  It sets the base bundle identifier and bundle name, version, deployment targets, language mode, concurrency, automatic signing with the project's development team (see "Building and Signing" below), and the Keychain service identifier, minimum supported Nextcloud version and privacy-policy and support URLs the `Info.plist` files pass on to the code.
  It is the only file that names a team — no target's `.xcconfig` does, and `project.pbxproj` must not — and a contributor's `Local.xcconfig` overrides it; the entitlements are assigned a level below, by `Cirruscope/Cirruscope.xcconfig` for both apps and by `Widgets/Widgets.xcconfig` for the extension, so the two test bundles carry none.
- `.swiftformat` and `biome.jsonc` are the two formatter configurations, and both sit at the repository root rather than beside the code they govern.
  That is not only tidiness: `Cirruscope/`, `Core/`, `macOS/`, `iOS/`, and `Widgets/` are synchronized folders, so anything placed inside one of them is compiled or copied into the built products of every target listing it, with no project-file change and no review step to notice.
  A tool whose configuration — or whose installed dependencies — lived in one of those folders would ship inside the app, which is also why the JavaScript tooling is a single Homebrew binary rather than an npm package.
  Neither file is referenced by `project.pbxproj` at all.
  Biome governs the JavaScript in `Cirruscope/Scripts/`, `macOS/Scripts/`, `iOS/Scripts/`, and `Website/js/`, and nothing else: its `files.includes` is an allowlist pinned to `*.js`, because Biome would otherwise format the stylesheets and the Xcode-owned JSON that `REUSE.toml` annotates precisely because it must never be hand-edited.
- The repository root also holds the Xcode project and the project's own documentation, licensing and repository configuration.
  `Cirruscope.xcodeproj/` is the Xcode project: `project.pbxproj` declares the five targets, the synchronized folders each one lists and the Rainmaker package the three product targets link, `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pins Rainmaker and its dependencies at the versions last resolved, `xcshareddata/xcschemes/` holds the two shared schemes `Cirruscope for macOS` and `Cirruscope for iOS`, and `xcshareddata/xcodecloud/manifest.json` is the Xcode Cloud manifest naming the target Xcode Cloud builds, written by Xcode rather than by hand.
  The project's main group also references `.github/` and `AppStore/` as synchronized folders, only so they can be browsed in Xcode: no target lists either, which is what keeps both out of every built product, and that must stay so.
  `README.md` is the developer landing page, with the workflow status badges, a pointer to the website and the unofficial-app disclaimer; `CONTRIBUTING.md` is the contribution workflow, from sign-off and AI-assistance disclosure to the code-signing setup and the checks to run; `CODE_OF_CONDUCT.md` is the conduct standard and the address to raise a concern with; and `GOVERNANCE.md` explains how the single-maintainer project is run and how feature requests are decided.
  `LICENSE` is the MIT license text the documents link to, `LICENSES/MIT.txt` is the same text where REUSE looks it up by its SPDX identifier, and `REUSE.toml` carries the licensing annotations for every file that takes no inline header (see "REUSE Compliance" below).
  `Local.xcconfig.example` is the template for the gitignored `Local.xcconfig` through which a contributor signs with their own team and bundle identifier, which the maintainer's own builds do without (see "Building and Signing" below).
  `.gitattributes` forces LF line endings on Swift, JavaScript and its tooling configuration, Xcode project and scheme files, xcconfigs, String Catalogs, shell scripts and plain-text files; `.gitignore` keeps build products, per-user Xcode data, `.DS_Store` and `Local.xcconfig` out of the repository; and `.swift-version` is the Swift version SwiftFormat reads.
- `Cirruscope/` contains the bundle identity, configuration and code the macOS and iOS app targets share, and is a member of both but not of the widget extension.
  `AppIcon.icon` is the app icon bundle (Icon Composer, gated to render on both platforms), `Bundle+name.swift` reads `CFBundleName` at run time, `Cirruscope.entitlements` declares the App Group and Keychain-sharing capabilities, `Cirruscope.xcconfig` carries the bundle identity both apps share and assigns both of them those entitlements, and `PrivacyInfo.xcprivacy` is the privacy manifest both apps carry, declaring the UserDefaults and file-timestamp APIs their code and Rainmaker use.
  It also holds the sign-in code both apps run and the extension must not: `LoginSession.swift` drives Nextcloud's Login Flow v2 in an `ASWebAuthenticationSession`, taking the window to anchor the grant sheet to from its caller, and `ServerAddress/` holds the address-sanitation pair the sign-in screens share — `ServerAddress`, the pure value type that normalizes typed or pasted input into the one canonical address the app connects to and displays, and `ServerAddressError`, the closed set of reasons an input cannot be one.
  `LoginSession` could not live in `Core/` at all, `ASPresentationAnchor` being `NSWindow`/`UIWindow`; the address pair could, and sits here anyway because only a sign-in screen normalizes an address somebody typed.
  `PageTitle.swift` shortens the title a Nextcloud page gives itself by dropping the instance's name from it, for the surfaces that fall back to a page title when they cannot name the app instead; it is here rather than in `Core/` for the same reason the scripts below are.
  `NextcloudSessionRoute.swift` recognizes the two addresses that change who an embedded web view is signed in as — the sign-in form a server redirects a lapsed browser session to, whose `redirect_url` it also reads back so that page can be silently re-requested with the stored app password, and Nextcloud's own sign-out link, which has to sign the account out of the app as well; it normalizes through `Core/ServerAppPath`.
  `WebViewDestination.swift` decides whether an address is the connected server's to display or the system's to open, on origin rather than host, which is what confines the web view — and the app password it carries — to one server while letting a `tel:` or `mailto:` link reach the application that can act on it.
  `SilentRetryBudget.swift` is the one silent retry allowed per lapsed session, keyed to the address being retried and released when the server answers it, so a retry that is never answered cannot go on to sign a working account out.
  All three are here rather than in `Core/` for the same reason the scripts below are, no widget having a web view to keep signed in, and all three are shared precisely because the two apps once each decided these questions alone and each got them wrong.
  `MediaCaptureDecision.swift` decides which pages are given the camera and the microphone without a prompt of the web view's own — the connected server's, judged on the origins of both the page and the frame asking, through the comparison `Core/SameOriginURL` makes.
  Both apps ask it, the Mac through its web view's `WKUIDelegate` and iOS through its `WebPage`'s device-sensor authorization, and it is not in `Core/` because no widget has a web view to grant anything to.
  `Scripts/` holds the JavaScript both apps inject — `SidebarToggle.js`, which clicks Nextcloud's app-navigation toggle, and `SidebarToggleState.js`, which reports whether that toggle exists and is open through a script message, re-reporting on every DOM mutation so it survives Nextcloud's single-page navigations — and `Script.swift` is the enum that loads them from the bundle — along with each app's own `Cirruscope.css`, which it wraps in the script that appends it to the document, so a stylesheet is injected exactly like any other script.
  The widget extension drives no web view, which is why these are here rather than in `Core/`.

  It also holds the persistence layer and the App Intents layer both apps run.
  `Persistence/` is the SwiftData stack: `AppDatabase` (owns the process-wide `ModelContainer` in the shared App Group container and opens it through the migration plan), `AccountStore` (the `@MainActor` repository that is the sole reader and writer of the connected account's data and of what the user set up on the device, and vends value types in place of its `@Model` records), the versioned schemas, `CirruscopeMigrationPlan`, `RefreshAdmission`, `AccountStoreNotificationName.swift` (the seven names the shared layer posts, named for the store because two files called `NotificationName.swift` in one target collide on the `.stringsdata` output Xcode derives from the base name), and `Models/` with the `@Model` records `Account`, `ServerApp`, `KeyboardShortcut`, `DevicePreferences`, `TalkConversation`, `ServerNote`, `ServerCollective` and `ServerCollectivePage`.
  `KeyboardShortcut` and `DevicePreferences` are what the user set up on the device — a shortcut keyed by the Nextcloud app identifier it opens, and the appearance choices — and have no relationship to `Account`, so a sign-out, which deletes the account and everything from the server, leaves them in place; see `DECISIONS.md` → "Why do the keyboard shortcuts and appearance settings outlive a sign-out, when everything from the server does not?".
  The store itself is one type across several files, one per domain: `AccountStore.swift` holds the account itself and its server apps, along with the two device records — the keyboard shortcuts and the appearance settings — and `AccountStore+Conversations.swift`, `AccountStore+Notes.swift` and `AccountStore+Collectives.swift` hold one domain each.
  Each keeps the same shape: upsert by the identity the server addresses the thing by, prune what it no longer lists, sort at the read, announce afterwards.
  A domain departing from that shape should say why next to the departure — the collectives do, their pages being listed per collective rather than all at once.
  `SchemaV2_1` is an intermediate schema no build runs on, through which a `1.1.0` store passes so that moving its shortcuts and appearance choices out of the account is written into the store before anything is dropped.
  One rule governs the schemas: a schema that has shipped is frozen into nested model copies and its version identifier never moves again, exactly one schema references the live models, and freezing one and introducing its successor therefore happen in the same change — see `DECISIONS.md` → "Why is every shipped schema frozen into nested model copies?".
  `RefreshAdmission` is whether what a refresh fetched may still be written when the fetch comes back: a sign-out does not stop a refresh already under way, so every write a refresh makes asks again, in the same main-actor turn as the write, whether the Keychain still holds the very credentials the fetch was made with and the store still records that server — the address itself excepted, which is how a store that lost it is repaired and so is asked of the Keychain alone; see `DECISIONS.md` → "Why does a refresh ask again, as it writes, whether its account is still signed in?".
  `AppEntities/` holds an entity and its query for each of the five types donated — server apps, Talk conversations, notes, collectives and the pages within them — and `AppIntents/` one `Open…Intent` for each, `OpenIntent` being the only thing that records the system protocol a phrase parameter needs and requiring its parameter be named `target`, which is why there is one intent per type rather than one over a union.
  It also holds `ServerAppShortcuts`, the single `AppShortcutsProvider` (so one parameter refresh, made by `ServerAppIndexer` alone, brings every query's values up to date), `SpotlightIndex`, which owns the donated-identifier bookkeeping every domain shares, one thin indexer per domain over it (four of them, `CollectiveIndexer` donating the pages along with their collectives), and the three seams between an entity and the app that opens it.
  `EntityActivation` turns one entity's identifier into a request — the store lookup, the route, and the collective page's fallback to its collective — and is shared by the intents and by a Spotlight tap, which is what stops the same entity being resolved two ways; `EntityOpening` is what each app installs its own way of opening into — once for the whole Mac app, once per window on iOS, the window most recently in front serving — and latches a request made before anything could serve it; `SpotlightSelection` reads which entity a Spotlight result names out of the activity the system delivers, **by type as well as by identifier**, since `42` is a note and also a collective and also a page.
  Each query also conforms to `IndexedEntityQuery` in a `+Indexed.swift` file, gated on the release that introduced the protocol, so the system can ask for a donation rather than only receiving the ones the app decides to make.
  `ServerAppIconThumbnail.swift` draws the artwork those surfaces are donated.
  `ServerConnection+AccountStore.swift` is the half of talking to a server that also writes what was learned to the store, recording what a validation found and the server's app list, and `ServerConnection+Conversations.swift`, `ServerConnection+Notes.swift` and `ServerConnection+Collectives.swift` do the same for one domain each: fetch it, map the server's answer to the domain's value type, and hand that to the store.
  Every one of those writes is admitted through `ServerConnection.record(_:fetchedFrom:as:requiringStoredAccount:_:)` in the first of those files, which asks `RefreshAdmission` and makes the write in one main-actor turn.
  `KeyboardShortcuts/` holds the shortcut value type the store's reserved-shortcut seam is typed over.
  Where one of these needs what only a platform can supply, that remainder lives in the platform's own folder — an `+AppKit`/`+UIKit` extension, or an `AccountStore+Shared.swift` per app — rather than behind an `#if os`.
- `Core/` contains what every target shares, the `Widgets` extension included, and is a member of all three.
  It is deliberately narrower than `Cirruscope/`: a synchronized folder puts every file it holds into every target that lists it, and `membershipExceptions` is a deny list, so an extension that listed the apps' shared folder would silently absorb each file later migrated there.
  It is grouped into subfolders by domain, which a synchronized folder carries into every target recursively — no project file names them and none has to.
  The names are the ones `Tests/` uses for the suites that cover them, so a type and its tests are found under the same word.
  `RemoteAssets/` is the one exception: the suites over its SVG renderer sit in `Tests/Icons/`, beside those over the top-level `SameOriginURL`.
  `Account/` is the connected account: `Credentials.swift` is the login name and app password from Login Flow v2, plus the HTTP Basic header value both web views sign themselves in with, which is the one place that value is spelled; `ServerAccount.swift` pairs one of those with the server address it authenticates against, which is what a single `Keychain` item holds, and builds the authenticated request the iOS web view is signed in with, the Mac's `WebViewController` attaching the same value to requests of its own; and `Keychain.swift` stores those credentials, keyed by server address.
  `Activity/` is the file activity the widget lists.
  `RecentActivity.swift` fetches it and closes over every way that can end — a quiet server, one whose activity app is switched off, an unreachable one, no account at all — so the widget cannot reach a different conclusion from the same answer than anything else would.
  `ActivityVerb.swift` is the four types the server's own `files` filter admits, and answers `nil` for anything else rather than badging an unrecognized type with a wrong glyph.
  `ActivityRow.swift` decomposes one activity into the parts a row draws, once, so no layout re-derives them.
  `ActivityFeedStore.swift` keeps the last good feed as JSON in the shared App Group container, which is what lets a failed refresh dim its rows rather than blank them — see `DECISIONS.md` for why that cannot be state on the timeline provider.
  `Notifications/` holds `UnreadNotifications.swift`, which fetches the notifications a server still has queued for the user and decides what that means for the app icon badge, so the iOS foreground refresh and its background job — which touches no store at all — ask the same question through the same code rather than through two implementations free to drift.
  `RemoteAssets/` is everything fetched from the server and kept.
  `AssetCache.swift` keeps on-disk copies of remote assets in the shared App Group's caches directory, revalidating them with their HTTP `ETag`; it lives here rather than in `macOS/` because that directory exists precisely so an app extension reaches the same copies.
  `ServerAppIcons.swift` downloads the server apps' icons, caches them by app identifier so a menu finds one without having asked the server anything, and renders them on demand.
  `ServerAvatars.swift` does the same for the profile photographs of the people an activity names, and caches *only* real photographs, never the monogram the server draws for a user who uploaded none, so that a cache miss means one thing.
  `ConversationAvatars.swift` is the third of these and keeps the picture Talk draws for each conversation, accepting only PNG and JPEG: the emoji and generated avatars arrive as SVG, and one that cannot be decoded leaves the Talk mark in place rather than being approximated.
  Its key carries the server, the account, the token, the avatar version and the appearance, because the version alone is not enough — for a one-to-one conversation the server derives it from a generic icon's path, so it is identical everywhere and never moves.
  That is also why every answer, a picture or the zero-length file recording a refusal, is asked about again once it is a week old.
  `SVG/` is the small renderer behind the icons: `SVGNumberScanner`, `SVGPathData` and `SVGTransform` read the attribute grammars, `SVGPresentationAttributes` and `SVGRenderingState` carry what an element inherits, `SVGDocumentParser` walks the document into `SVGShape`s, and `SVGGlyph` with `SVGGlyphRasterizer` fits and draws them — enough for the monochrome glyphs Nextcloud ships and deliberately no more, since neither platform will decode an SVG for the app.
  It sits under `RemoteAssets/` because the icons `ServerAppIcons` downloads are the reason it exists and the only documents it reads: `ServerAppIcons` rasterizes them for the menus and hands the parsed glyph to `Cirruscope/ServerAppIconThumbnail`, which draws it into the donated artwork.
  `Conversations/` is the Nextcloud Talk conversations the account takes part in: `ConversationTransferObject` is the value snapshot both apps pass around, `+Sorting` holds the one order they are listed in (most recently active first, not alphabetically — see `DECISIONS.md`), `ConversationKind` is what kind of conversation something is as an open set of numbers rather than a closed enum, and `ConversationWebRoute` builds the address that opens one and names the app that owns it.
  Three of the four route types carry that `appID` (`ConversationWebRoute`, `NoteWebRoute` and `CollectiveWebRoute`, whose identifier serves the collective's pages as well), and it is not a second fact but the same one written where it can be used: Nextcloud serves an app under `/apps/<app id>/`, which the Notes and Collectives routes spell out and Talk's own pages follow, and the App Intents entities need it to find the app's icon.
  That route is appended to the server address rather than resolved from the root, as the Notes and Collectives routes are too, because a path the app itself knows carries none of the instance's web root; what sets Talk's apart is only that it is registered at the server's own root rather than under `/apps/spreed/`.
  `Collectives/` is the collectives the account is a member of and the pages within them: two value snapshots with their own orderings — collectives alphabetically, pages by how recently they changed, which is the same rule applied twice rather than an inconsistency — and two routes.
  `CollectivePageWebRoute` and `CollectiveWebRoute` are read out of the Collectives app's Vue router rather than a `routes.php`, that app declaring only a catch-all on the server: a collective is `<slug>-<id>` and a page `<slug>-<id>` within it, with the name and the ancestor-path forms kept as the fallbacks an instance predating slugs needs.
  The path fallback is the only branch that also carries the page's file identifier, as a hedge, and a page whose address cannot be built at all opens its collective instead, which `EntityActivation` decides for the intent and a Spotlight tap alike.
  `Notes/` is the notes in the account's Nextcloud Notes app: `NoteTransferObject` is the value snapshot, `+Sorting` holds the one order they are listed in (favourites first, then most recently changed), and `NoteWebRoute` builds the address that opens one.
  The value type carries a title and a category and deliberately has **no field for a note's text** — that is dropped where the server's answer is mapped, so nothing downstream can hold one; see `DECISIONS.md`.
  `ServerApps/` is the Nextcloud apps a server offers.
  `ServerAppTransferObject.swift` is the value snapshot of one app both apps list in their menus, with `ServerAppTransferObject+Sorting.swift` holding the one order they are ever listed in and `ServerAppTransferObject+Resolution.swift` the one rule for deciding which of them a loaded page belongs to — the Mac reuses a window by it, the iPhone titles its navigation bar by it.
  `ServerAppPath.swift` is what that rests on: it reduces a URL to the path it addresses within one instance, shedding the `index.php` segment an instance without pretty URLs serves everything under and the web root an instance installed in a subdirectory writes into every path it names, so two spellings of one page compare equal; it also carries the short table of routes an app registers at the server's own root rather than under its own prefix, Talk's `/call/<token>` conversation route being the one such route a current server has that belongs to an app the navigation endpoint offers.
  Six files stay at the top level because they belong to no one domain and are used across several.
  `AppGroup.swift` resolves the shared App Group container identifier from the target's `Info.plist`, and the container itself, trapping rather than answering `nil` when the system reports the build is not entitled to it — see "Building and Signing" for why a build without the App Group is an error rather than a state to degrade into.
  `InfoPlist.swift` reads the statically configured values every target needs out of its own `Info.plist` — the minimum supported Nextcloud major version, the application name, the Keychain service identifier, and the privacy-policy and support URLs.
  `Logging.swift` adds the `Logger(for:)` convenience initializer that every behavioural type uses to build its own `os` logger, with the running bundle's identifier as subsystem and the type's name as category.
  `CirruscopeError.swift` is the shared error type thrown by app-level facilities.
  `SameOriginURL.swift` is every address the app is allowed to attach the user's app password to, and it builds them two ways for two kinds of caller.
  A path the *server* named is resolved against the server's address, because such a path already carries the instance's web root; a path the *app* knows is appended instead, because it does not, and resolving one from the root silently moves it to the host's own root.
  Both refuse anything landing on another origin, and the appending form additionally refuses a dot segment, which would climb out of the web root while staying on the origin — see `DECISIONS.md`.
  `ServerConnection.swift` builds `Rainmaker.Server` instances, validates a server's version against `InfoPlist.minimumSupportedServerMajorVersion`, and revokes an app password on sign-out; it writes nothing, the halves that record what a validation and each refresh found living in `Cirruscope/ServerConnection+AccountStore.swift` and its per-domain siblings.
  `Assets.xcassets` holds the color assets — the accent color and the widget background — which the widget reads by name rather than restating as literals.
  Nothing here may depend on AppKit or UIKit; that is what makes it usable from an app extension — and that rule is what keeps `LoginSession` in `Cirruscope/` instead.
- `macOS/` contains the Swift source code, resources, and configuration for the macOS app target, alongside its own `macOS.xcconfig`.
    - `AppDelegate/` contains `AppDelegate.swift`, the application delegate that owns the web windows and builds the server-app items in the View and Dock menus, and its three extensions: `AppDelegate+NSWindowRestoration.swift`, which recreates the web windows AppKit saved at quit, `AppDelegate+ReservedShortcuts.swift`, whose `reservedShortcutName(for:)` names the fixed menu item a shortcut would collide with, and `AppDelegate+Spotlight.swift`, whose `openSpotlightSelection(_:)` opens what a selected Spotlight result names.
    - `Web/` contains `WebViewController` with its `WKNavigationDelegate`, `WKUIDelegate`, and menu-validation extensions, the `WebWindow`/`WebWindowController` that host it — the latter with its `NSWindowDelegate` extension, which records the window's size as the one the next web window opens at and tells the hosted page when the window enters or leaves native fullscreen — `WebWindowFrame.swift`, which owns that remembered size through AppKit's named-frame mechanism, `NextcloudHeaderHeight.swift`, which remembers how tall the connected server draws the header bar those windows use as their title bar, so the standard window buttons are centered in a height the server reported rather than one the app assumed, `macOSScript.swift`, which enumerates the bundled JavaScript resources and loads their source from the bundle on demand, and `WebAccentColor.swift`, which resolves the app's effective accent color into the sRGB hex string and brightness verdict forwarded into the page.
    - `Downloads/` contains the download feature: `DownloadManager.swift` is the `WKDownloadDelegate` facility that coordinates every transfer decoupled from the UI, `DownloadManager+WKDownloadDelegate.swift` is its delegate conformance, `Download.swift` is the runtime model of a single transfer, and `DownloadViewController` with its table data-source and delegate extensions and `DownloadTableCellView` presents the download history.
    - `Settings/` contains the view controllers of the settings window's General, Appearance and Speed Dials tabs (`GeneralSettingsViewController`, `AppearanceSettingsViewController`, and `ServerAppsViewController` with its table extensions), `ShortcutRecorderView`, the control each Speed Dials row records a server app's shortcut in, and `ShortcutRecordingTableView`, the table that lets such a control become first responder from a plain click.
      It also holds `NotificationName.swift`, which declares the in-process notifications only macOS posts and observes: those `DownloadManager`, `NotificationMonitor`, `AccentColorMonitor` and `NextcloudHeaderHeight` post.
      The settings tabs post none of their own: a changed choice is announced by the account store, whose names are declared in `Cirruscope/Persistence/AccountStoreNotificationName.swift`.
    - `ServerAddress/` contains the AppKit half of signing in: `ServerAddressViewController` with its text-field-delegate extension, and `ServerAddressFormatter`, the `Formatter` that rewrites the field to the canonical address as soon as editing in it ends.
      The value types it normalizes through, and the Login Flow v2 driver it hands the validated server to, are shared with iOS and live in `Cirruscope/`.
    - `Views/` contains the two custom views `WebViewController` draws around its web view: `BackgroundImageView`, which fills its bounds with the themed backdrop shown during the initial page load, center-cropped the way Nextcloud's own background is, and `StateOverlayStackView`, the rounded card shown over that backdrop while a page loads or after a load fails.
    - `Models/` contains `KeyboardShortcutTransferObject+AppKit.swift`, which turns a stored shortcut's flags back into the `NSEvent.ModifierFlags` a menu item is assigned.
      It is the AppKit half of a value type that lives in `Cirruscope/KeyboardShortcuts/`, because the shared store's reserved-shortcut seam is typed over it, and iOS needs nothing from it, since it assigns no key equivalent to a server app, the iPad's View menu included.
    - `Persistence/` contains the parts of the shared account store that are this app's alone.
      `AccountStore+KeyboardShortcuts.swift` holds the three reads that decide which app a keystroke actually reaches, each comparing through the AppKit-bound `ShortcutMatching`; `AccountStore+Shared.swift` builds the process-wide instance, passing the reserved-shortcut lookup that answers from the live `NSApp.mainMenu`.
      The stack itself — `AppDatabase`, `AccountStore`, the versioned schemas, the migration plan and the `@Model` records — lives in `Cirruscope/Persistence/`.
    - `AccentColorMonitor.swift` is the process-wide monitor of the macOS accent-color preference and light/dark appearance that announces `Notification.Name.accentColorDidChange` so every open web view re-applies the accent color.
    - `ServerAppIconThumbnail+AppKit.swift` resolves the one colour in the donated artwork that AppKit has to name — the secondary label colour, taken in the light appearance because the plate is white in both.
      The artwork itself is drawn by `Cirruscope/ServerAppIconThumbnail.swift`, its geometry and its PNG encoding being Core Graphics and ImageIO and identical on both platforms.
      See `DECISIONS.md` for what was measured before settling on a little white window.
    - `NSImage+ServerAppIcon.swift` turns the bitmap `Core/ServerAppIcons` renders into the 16-point template image the View menu and the Speed Dials tab show beside each app.
      From macOS 27 on, the View menu shows it only because `AppDelegate`'s factory asks for `NSMenuItem.ImageVisibility.visible`, AppKit hiding menu item images by default for an app built with that SDK — see `DECISIONS.md`.
      The Dock menu is built by the same factory and shows no image regardless: the Dock renders that menu out of process and drops `NSMenuItem.image`, which was measured rather than assumed.
    - `Notifications/` contains `NotificationMonitor`, which watches the server for unread notifications, keeps the Dock badge current, posts a banner through `UserNotifier` for each newly arrived one while no web window is open to raise its own, and reports a revoked app password so the app can require a new sign-in.
    - `ShortcutMatching.swift` defines when two key equivalents mean the same keystroke to AppKit, the single comparison both the reserved-shortcut lookup in `AppDelegate` and the duplicate-shortcut lookups in `AccountStore` use.
    - `UserNotifier.swift` presents notifications from the web interface, download-completion notifications from `DownloadManager`, and the server's own notifications from `NotificationMonitor` in the macOS Notification Center, and handles a click on each: it brings the originating web window forward, reveals the downloaded file in Finder, or opens the notification's link in a web window.
    - `Cirruscope.css` is the stylesheet injected into the web view.
    - `Scripts/` contains the JavaScript resources only macOS injects or evaluates: `WindowDrag.js`, `HeaderHeight.js`, `SidebarShortcut.js`, `AppearanceAttributes.js`, and `NotificationBridge.js`.
      The two both apps share live in `Cirruscope/Scripts/`; `macOSScript` enumerates these five, `Script` enumerates those two and the `styleSheet` case that wraps `Cirruscope.css` in the script appending it to the document, and `installUserScript(_:injectionTime:)` takes a loaded source string so it can install a script from either.
    - `Base.lproj/Main.storyboard` defines the macOS app's user interface; its strings are localized through `mul.lproj/Main.xcstrings`.
    - `Info.plist` is the macOS app's information property list, carrying the values `Core/InfoPlist.swift` and `Core/AppGroup.swift` read and the App Transport Security exception that allows arbitrary loads (see `DECISIONS.md`).
      The user-facing usage descriptions macOS shows in its permission prompts are not in that file — they come from the target's `INFOPLIST_KEY_*` build settings and are localized through `InfoPlist.xcstrings`.
    - `Localizable.xcstrings`, `InfoPlist.xcstrings`, and `AppShortcuts.xcstrings` are the macOS app's String Catalogs, covering German, French, and Spanish — see "Localization Instructions" below.
- `macOSTests/` contains the tests for what only macOS does (see "Testing" below), grouped into one subfolder per feature domain, alongside the target's own `macOSTests.xcconfig`.
    - `KeyboardShortcuts/` covers the keyboard shortcut domain: the shortcut-matching and display-string suites, the `ShortcutFixture` corpus they share, and `KeyEquivalentProbe`, the AppKit oracle one of them measures against.
    - `Account/` covers the account store's keyboard shortcuts, which need AppKit because a shortcut in these cases is a `ShortcutFixture` built from `NSEvent.ModifierFlags`: the shortcut-assignment, duplicate-suppression and shortcut-survival suites — the last covering a shortcut outliving its app being pruned and the account being deleted, and applying again when a server offers the app — and `ReservedShortcuts`, the reserved-shortcut stand-in these suites hand the shared `AccountStoreHarness`, built out of `ShortcutMatching`.
    - `Appearance/` covers the appearance domain: the `WebAccentColor` suite pinning the hex-string shape the accent color crosses into JavaScript as, and the brightness threshold it shares with Nextcloud's own.
    - `Icons/` covers the artwork donated to Spotlight for a server app, a white window plate with the app's glyph in it, asserting colour and opacity rather than shape.
      It is a macOS suite because the glyph's ink is the one part of that artwork each platform answers for itself, here `NSColor.secondaryLabelColor` resolved in the light appearance, and resolving it in the wrong appearance is one of the ways the artwork goes wrong.
    - `ServerAddress/` holds `ServerAddressFieldNormalizationTests`, which drives a real `NSTextField` carrying `ServerAddressFormatter` to pin when AppKit applies it.
    - `Windows/` covers the web windows' own geometry: the `WebWindowFrame` suite, which pins the fullscreen rule directly and measures `NSWindow.saveFrame(usingName:)`/`setFrameUsingName(_:)` against a second, freshly created window rather than restating what those two do; the `NextcloudHeaderHeight` suite, which pins which reported header heights are believed at all, what survives the round trip through `UserDefaults`, and which reports are announced; `WebWindowButtonPlacementTests`, over the pure function deciding where the standard window buttons go in that header — asserting that a button's center coincides with the header's whatever either measures, which is the property a compiled-in height could not hold; and `WebWindowButtonClearanceTests`, over its horizontal counterpart deciding how far in the page must start to clear those buttons — asserting that fullscreen needs none, that whatever is answered leaves the last button behind it, and, against a window button AppKit itself vends, that an ordinary window's answer is still the number `macOS/Cirruscope.css` falls back to.
- `Tests/` contains the tests for code the two apps share, and is a member of *both* test targets, so every suite in it runs twice — once against each app module.
  `AppIntents/` covers the path from a donated entity to something opening — what App Intents' own identifier carries, what a tapped Spotlight result resolves to for each of the five types, what each identifier activates, the latch that holds a request arriving before any screen exists, and which of several windows' openers serves one; `Account/` covers the connected account's stored data, the store that owns it and the migration it is opened through, whether a refresh a sign-out overtook may still write, plus the Keychain enumeration both platforms answer differently; `Appearance/` covers the device's appearance settings as the store keeps them, apart from any account; `Activity/` covers the widget's feed rows and verbs; `Collectives/`, `Conversations/` and `Notes/` each cover their domain through a shared fixture and three suites, over what the store does with a refresh's results, how the domain is ordered, and the address that opens one of its items; `Configuration/` covers the Keychain service identifier and the reasons each app's property list gives the system for the camera, the microphone and the local network; `Notifications/` covers what an unread-count fetch means for the badge; `Icons/` covers `Core/`'s SVG renderer, its same-origin rule, when a conversation's cached picture is asked about again, over an `AssetCache(directory:)` of its own rather than the shared one, and the two ways of filling the donated Spotlight plate that are not an app's glyph — an emoji and a conversation's own picture — asserted as colour and opacity rather than as shape, since what that artwork exists to prevent was never a layout problem; `ServerAddress/` covers what a typed or pasted address normalizes to and the Foundation behaviour that rests on; `ServerApps/` covers reading a URL as a path on one instance, deciding which app a page belongs to, and the page-title shortening the second of those falls back to; and `WebView/` covers the four decisions both web views share — recognizing the connected server's two session routes and reading back the address a sign-in form's `redirect_url` names, telling an address the web view should display from one the system should open, the bookkeeping of the single silent retry a lapsed session is allowed, and which pages are given the camera and the microphone, asked about the origins a real `WKWebView` reports through `SecurityOriginProbe`.
  It carries no `.xcconfig`: each test target keeps its own.
    - A domain can be split across here and a platform folder, and `ServerAddress` is: the two suites above are pure and live here, while the suite driving a real `NSTextField` lives in `macOSTests/ServerAddress/`.
      The split follows what a suite *needs*, not what it is about.
    - `Account/` holds `ServerAppUpsertTests`, `ConnectedAccountTests` over the account's lifecycle, including what survives its deletion, `RefreshAdmissionTests` over whether a refresh overtaken by a sign-out may still write what it fetched, `StoreMigrationTests` and `KeychainEnumerationTests`, together with what the account suites of both test targets share: the `ServerAppFixture` corpus, and `AccountStoreHarness`, which gives each case its own `AccountStore` over an in-memory SwiftData container.
      The app-upsert suite also covers the order `AccountStore.serverApps` lists the apps in, that order being a property of the snapshot rather than of any one menu.
      `StoreMigrationTests` writes a store in each schema Cirruscope has shipped and reopens it at the current one, so it uses `StoreFileHarness` instead, which gives each case a store on disk, an in-memory container never being reopened.
      Its `1.0.0` case is disabled, since it aborts the test host whenever another suite runs beside it, until a store written by the `1.0.0` models is committed as its fixture; a case for a store left at the intermediate `SchemaV2_1` step pins that an interrupted migration still finishes.
- `iOS/` contains the Swift source code, resources, and configuration for the iOS app target, alongside its own `iOS.xcconfig`.
  The target was created ahead of any iOS release for two reasons that still hold — a widget extension cannot be rendered in Xcode's Previews canvas from a macOS target, and a second target compiling the shared folders is the only thing that keeps them honest about what is actually platform-neutral — and it is now also where the side product described under "Platform Scope" is built.
  What works today: Login Flow v2 sign-in through the shared types in `Cirruscope/`, an account restored from the Keychain at launch, a web view signed in by HTTP Basic authentication and silently signed back in when the browser session behind it lapses, the server-app menu with each app's own icon — as the navigation bar's title menu and, on an iPad, in the View menu of the menu bar, which opens the chosen app in whichever window is in front — an unread-notification count that badges the app icon from both the foreground and a background refresh, the camera and the microphone for calls in Talk, granted to the connected server without WebKit's own prompt as on the Mac and with videos playing inline rather than full screen, and a logout that revokes the app password on the server, whether it is asked for in the app's own account menu or in Nextcloud's.
  It has persistence as well: `Persistence/AccountStore+Shared.swift` builds the shared store for this app, the server address is recorded at sign-in and deleted at sign-out, and the app list survives a relaunch instead of being re-fetched into memory on every launch — which is also what lets Spotlight and the Shortcuts app be offered those apps before the server has answered anything.
  `ServerAppIconThumbnail+UIKit.swift` resolves the colour the donated artwork's glyph is drawn in, and `AppShortcuts.xcstrings` is this target's own App Shortcuts table, phrases being extracted per target like every other String Catalog.
  What does not exist yet: the appearance settings macOS keeps in the same store, the keyboard shortcuts macOS lets a user assign to a server app, and few tests of its own — `iOSTests/` covers the background refresh's property-list configuration, the web view's insets and its user agent, with everything shared living in `Tests/` and running against this target as well.
  Its user interface is SwiftUI: `iOSApp.swift` is the `App` entry point and attaches `ServerAppCommands.swift`, the `Commands` listing the server apps in the iPad's View menu — with `FocusedValues+DisplayScale.swift` beside it, the focused value through which the window in front tells that menu its screen's scale, command content being laid out in no window and so at a scale of one — and `ContentView.swift` chooses between the sign-in screen and the web view on whether an account is configured.
  `Views/` holds those screens — `ServerAddressView`, which signs in through the shared types in `Cirruscope/`, and `NextcloudView`, which hosts the `WebPage` and titles its navigation bar with the name of the Nextcloud app the loaded URL resolves to, falling back to the page's own shortened title where it resolves to none, and which publishes its `WebPage` and its display scale as focused scene values, which is how the View menu finds the window in front and renders its icons sharp — alongside `ServerAppMenuItems`, the list of server apps both menus draw, so the two cannot list the same app differently, and `LoadingOverlay`, the opaque cover it overlays that web view with for as long as `WebPage.isLoading` says a document is on its way in.
  `Models/` holds `Store`, the observable app state that owns the connected account and the `Rainmaker.Server` built from it, and decides which request may open a server app; `AppNavigationBridge`, the `WKScriptMessageHandler` that receives what the page reports about its app-navigation toggle so the toolbar control can appear only where there is one; `NotificationsPanelBridge`, the handler that receives what the page reports about Nextcloud's notifications menu, logging which candidate selector matched it and letting `NextcloudView` fetch the unread count again once its panel closes; and `WebPageInsets`, the value type carrying one measurement of how much of the web view the app's own interface covers.
  `Web/` holds `iOSScript`, the enum that loads the JavaScript only iOS injects, `SafariUserAgent`, which builds the application name the web view appends to its user agent so Nextcloud does not read it as an unrecognized browser, and `NextcloudNavigationDecider`, the `WebPage.NavigationDeciding` conformer that cancels a navigation to the server's sign-in form and re-requests the page behind it with the stored app password — signing the user out only when that retry is itself refused — and that widens Nextcloud's own sign-out link into signing the account out of the app.
  `UIImage+ServerAppIcon.swift` turns the bitmap `Core/ServerAppIcons` renders into the template image the title menu and the iPad's View menu show beside each app.
  `Notifications/` holds the two iOS-only halves of the unread-notification badge: `AppIconBadge`, the app's one caller of `UNUserNotificationCenter`, and `NotificationRefreshTask`, the background job `iOSApp` registers through SwiftUI's `backgroundTask(_:)` and which does nothing but fetch the count and write that badge.
  `Scripts/` holds the JavaScript `iOSScript` loads — `SafeAreaInsets.js`, which publishes each `WebPageInsets` measurement onto `<html>` as the custom properties the stylesheet insets Nextcloud's content by, and `NotificationsPanelState.js` and `NotificationsPanel.js`, which between them resolve Nextcloud's notifications bell against a list of candidate selectors, report which one matched, and click it — `Cirruscope.css` is the stylesheet injected into the web view, and `Localizable.xcstrings` and `InfoPlist.xcstrings` are the target's own String Catalogs.
  `Info.plist` carries the values `Core/InfoPlist.swift` and `Core/AppGroup.swift` read, as on macOS, and the same App Transport Security exception allowing arbitrary loads as the macOS app and the widget extension.
  The usage descriptions its permission prompts show are not in that file: as on macOS, they come from the target's `INFOPLIST_KEY_*` build settings and are localized through `InfoPlist.xcstrings`.
  It also declares what the background refresh needs: the `fetch` background mode, and the task identifier, once under `NotificationRefreshTaskIdentifier` for `NotificationRefreshTask` to read and once in `BGTaskSchedulerPermittedIdentifiers`, both substituted from one build setting in `iOS.xcconfig`.
- `iOSTests/` contains the tests for what only iOS does, alongside the target's own `iOSTests.xcconfig`: `Notifications/` holds `NotificationRefreshTaskConfigurationTests`, which reads the built property list to confirm the background refresh is configured the way the system requires, and `WebView/` holds `WebPageInsetsTests`, over the value type that turns a SwiftUI measurement into the call publishing it into the page, and `SafariUserAgentTests` with its probe.
  Everything shared it runs comes from `Tests/`.
- `Widgets/` contains the WidgetKit extension, alongside its own `Widgets.xcconfig`.
  One target serves both platforms rather than one per platform — `Widgets.xcconfig` sets `SDKROOT = auto` and lists both in `SUPPORTED_PLATFORMS`, so each app embeds the extension built against its own SDK — and platform differences live in `[sdk=…]`-qualified build settings rather than in duplicated sources.
  `WidgetsBundle.swift` is the `@main` entry point listing the widgets on offer.
  The activity widget is the one there is: `ActivityWidget.swift` declares it and holds the previews, which render only with an iOS Simulator destination selected; `ActivityTimelineProvider.swift` is what WidgetKit asks for entries, and `ActivityEntry.swift` is one of those — a closed set of what a card can be showing, so a failure cannot arrive as an empty feed.
  `ActivityWidgetView.swift` is the only place that knows how a family maps onto a layout, and `ActivityRowView`, `ActivityAvatarView`, `ActivityHeaderView`, `ActivityMessageView` and `ActivityRedactedView` draw what they are given without asking how big the widget is.
  `ActivityStyle.swift` is every colour in one place, and carries no literal: the two the app owns come from `Core/Assets.xcassets` and the rest are the system's own, which is why it needs no `ColorScheme` — see `DECISIONS.md`.
  `Localizable.xcstrings` is the target's own String Catalog.
  `Info.plist` declares the WidgetKit extension point and carries the values `Core/InfoPlist.swift` and `Core/AppGroup.swift` read, with the same App Transport Security exception as both apps.
  It deliberately declares no `NSLocalNetworkUsageDescription`, although the extension reaches the server itself: an app extension shares its containing app's local network permission, and the reason belongs in the app's property list alone.
  `PrivacyInfo.xcprivacy` is the extension's own privacy manifest, since the extension is a bundle of its own and the apps' copy in `Cirruscope/` does not reach it: it declares the file-timestamp APIs that `Core/` and Rainmaker compile into the extension as well.
- `Website/` contains the project's public website, deployed to GitHub Pages by `.github/workflows/website.yml`.
  It carries the polished, user-facing counterpart of the decisions recorded in `DECISIONS.md`.
- `AppStore/` holds the texts entered into App Store Connect and TestFlight, which nothing else in the repository would otherwise show — not git, not a review, not an agent.
  Each text is one file at `AppStore/<marketing version>/<platform>/<language>/<field>.txt`.
  `<marketing version>` is the `MARKETING_VERSION` the texts were or will be submitted with.
  A folder for a release still to come is that release's draft; a folder whose version has a git tag of the same name was published and is a record of what was published, not edited afterwards.
  `<platform>` is `macOS` alone: an `iOS` folder is added only once an iOS release is planned, which, per "Platform Scope", it is not.
  `<language>` is App Store Connect's own English name for one of the app's localizations — `English`, `German`, `French` and `Spanish` — rather than a locale code.
  `<field>` names the field the file is pasted into, and each has a limit counted in characters, without the trailing newline every file ends with:
    - `Description.txt` is the App Store description and also TestFlight's Beta App Description (4000);
    - `WhatsNew.txt` is "What's New in This Version" (4000);
    - `Keywords.txt` is the comma-separated keywords (100);
    - `Subtitle.txt` is the subtitle below the app's name (30);
    - `WhatToTest.txt` is TestFlight's "What to Test" for that version's builds, holding the latest build's text, the earlier ones being in git history (4000).
  A field without a file is one whose text was never recorded, as 1.1.0's "What to Test" was not.
  The files are plain text pasted verbatim, so their line breaks are part of the text: neither the one-sentence-per-line rule nor an inline SPDX header applies to them, and `REUSE.toml` covers them as `AppStore/**`.
  How the translations are derived is under "Localization Instructions", and when the texts must change is under "Documentation Instructions".
- `.github/CODEOWNERS` names `@i2h3` as the owner of every path, so GitHub requests that account's review on every pull request.
- `.github/ISSUE_TEMPLATE/` contains the GitHub issue forms for feature requests and bug reports, and `config.yml`, which keeps blank issues enabled and links the website from the issue chooser.
- `.github/PULL_REQUEST_TEMPLATE.md` pre-fills a new pull request's description with a prompt for what it does and why, and a checklist of sign-off, AI-tool disclosure, formatting, REUSE and test steps; it carries no inline SPDX header, for the reason given under "REUSE Compliance".
- `.github/workflows/` contains the GitHub Actions workflows used for DCO checks (`dco.yml`), Swift formatting (`swiftformat.yml`, on the macOS image that ships SwiftFormat), JavaScript formatting and linting (`biome.yml`, which installs Biome on `ubuntu-latest` because no runner image carries it), deploying the website (`website.yml`), REUSE compliance (`reuse.yml`), release SBOM generation (`sbom.yml`), and closing inactive pull requests and inactive issues labelled `question` (`stale.yml`, which marks them stale after seven days and closes them seven days later).
  None of them compiles anything: building and testing is Xcode Cloud's (see "Building and Signing").
- `DECISIONS.md` is the project's design-decisions FAQ: a plain-language record of why key architecture and product choices were made, maintained per the "Design Decisions" instructions below.

## Code Style

- This project is set up to use SwiftFormat for Swift and Biome for JavaScript, the latter configured by `biome.jsonc` in the project root.
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
  The flag is what makes the command agree with `biome.yml`: several recommended rules report at warning level, and without it such a diagnostic passes locally while that workflow still rejects it.
- Everything the app calls into the page from Swift hangs off one `window.Cirruscope` namespace, assigned idempotently (`window.Cirruscope = window.Cirruscope || {};`) by each script that contributes a member, because injection order is not something a script should have to assume.
  What scripts tell *each other* stays on `<html>` attributes instead: a `window` global is visible only in the content world that defined it, and whether an evaluated script and a user script share a world fails silently when it is wrong.
  The namespace holds what Swift calls; the DOM holds what scripts tell each other.
- Do not place business or user interface logic into data transfer objects.

## Building and Signing

**Xcode 27 or newer is required to build.**
Not a preference for something current: the `IndexedEntityQuery` conformances in `Cirruscope/AppEntities/*+Indexed.swift` name `CSSearchableIndexDescription`, which does not exist in the SDK Xcode 26.6 ships, and `@available` cannot conjure a symbol the SDK has never heard of — an older toolchain fails with "Cannot find type … in scope" before availability is ever consulted.

**Every build signs for real, with a team and the entitlements.**
Debug, a test run and Release alike: there is no ad-hoc configuration, and no runtime fallback for a build that lacks the entitlements.
The apps and the widget extension share their data through the App Group container — the store, the cached assets and the widget's last good feed — so a build that cannot reach it is not a degraded build of the app but a broken one.
This is not theoretical: TestFlight build 1.2.0 (50), archived by Xcode Cloud while the entitlements were set only in the gitignored `Local.xcconfig` and the tracked configuration signed ad-hoc, shipped with neither the App Group nor the Keychain access group, in the app or in the extension.
The fallbacks the code then had hid it: the app silently opened an empty store in its own container instead of the shared one, so 1.1.0 users found their keyboard shortcuts and appearance settings gone, although they sat intact in the App Group container and return with a correctly signed build.
The stores such builds left in an app's own container are abandoned, not migrated.

- `Cirruscope.xcconfig` sets `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM`, the maintainer's team, above its trailing `#include? "Local.xcconfig"`, so a contributor's `Local.xcconfig` overrides it.
  It is the only file naming a team: no target's `.xcconfig` does, and `project.pbxproj` must not either.
  The team ID is no secret, every binary signed with it carrying it.
- `CODE_SIGN_ENTITLEMENTS = Cirruscope/Cirruscope.entitlements` is assigned a level below, by `Cirruscope/Cirruscope.xcconfig` for both apps and by `Widgets/Widgets.xcconfig` for the extension, each after its include of the root.
  The two test bundles, which include only the root, therefore carry no entitlements, and a root `Local.xcconfig` cannot reassign them for the three products, which is intended.
  `REGISTER_APP_GROUPS = YES` sits beside it in the same two files rather than in `project.pbxproj`; it is a macOS-only build setting, letting automatic signing register the App Group the entitlements name when it signs for the Mac.
- No target names a provisioning profile.
  Automatic signing rejects a `PROVISIONING_PROFILE_SPECIFIER` once a team is set, so leave the profile to it rather than naming one again.
- From the command line, automatic signing registers identifiers and creates or downloads profiles only when it is allowed to: pass `-allowProvisioningUpdates` to every `xcodebuild` that builds, as the commands under "Testing" do.
  Xcode does the same on its own for the Apple ID signed in to its Accounts settings.
- **Nothing at build time checks for the entitlements, and nothing has to.**
  With the team and the entitlements in the tracked configuration, Xcode either embeds them or fails while signing.
  Only a deliberate override gets around that — `CODE_SIGNING_ALLOWED=NO` or `CODE_SIGN_IDENTITY=-` on the command line or in a `Local.xcconfig`, or `CODE_SIGN_ENTITLEMENTS=` on the command line or in a `Local.xcconfig` inside a target folder (see below) — and the project supports no build made that way, an unsigned iOS compile check included.
- **A build without the entitlements traps at launch, by design.**
  `AppGroup.containerURL` traps when `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` answers `nil`, which is how iOS reports a missing entitlement.
  macOS answers a URL of the expected form even for a build that is not entitled, and the App Sandbox then refuses whatever is opened under it, so there the failure surfaces in `AppDatabase.container`: the open fails, is retried once after quarantining the store — moving it to `.quarantine` siblings, never deleting it — and a second failure is logged as a fault and traps.
  `AssetCache` caches in the App Group's `Library/Caches/Assets` or not at all, logging a fault when that directory cannot be created, and `ActivityFeedStore` has no location but the container either.
  The macOS widget extension opens no store, so an unentitled build of it does not trap at all: it shows only as `AssetCache`'s fault and `ActivityFeedStore`'s failed writes.
  The trap is the point: it is what a build that would otherwise show its user none of their data looks like before anyone ships it.
- **A `ModelConfiguration` naming an App Group traps rather than throwing when the build is not entitled to it.**
  `ModelConfiguration(groupContainer: .identifier(…))` resolves the container inside its *initializer*, and a refused lookup is `fatalError("Unable to find App Group Container in Entitlements: …")` from `SwiftData/DataUtilities.swift` — `containermanager` logs `client is not entitled` immediately before it.
  There is no `try` to write and nothing to catch, so no amount of `do`/`catch` around the `ModelContainer` below it helps.
  `AppDatabase.container` therefore resolves `AppGroup.containerURL` *before* constructing any group configuration, so that an unentitled iOS build stops at a trap whose message names the cause rather than inside SwiftData.
  The store is a `static let` reached from `Store.restored()` in `iOSApp.init()`, so either trap fires at launch.
  SwiftData's own was diagnosed only by installing such a build on a simulator and reading its log, two guesses from the crash stack alone having been wrong.
- **Whether the macOS widget can read the app's credentials is unverified.**
  The `keychain-access-groups` entitlement puts the widget extension in the apps' Keychain access group, which on iOS is what lets it read the item the app wrote.
  On macOS, though, the credentials live in the file-based Keychain, where access to an item is governed by its access control list rather than by `keychain-access-groups`, so do not assume the extension there reads the item the app wrote.
- **A contributor signs with their own team and their own identifiers.**
  Copy `Local.xcconfig.example` to `Local.xcconfig` next to it (gitignored, never committed) and fill in both of its values, `DEVELOPMENT_TEAM` and `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER`; the maintainer needs no `Local.xcconfig` at all.
  The identifier has to change along with the team because the shipping identifiers and `group.de.i2h3.cirruscope` are registered to the maintainer's team, and no other team can claim them; every identifier the project uses — the apps', the extension's `.widgets`, the test bundles' `.tests`, the App Group, the Keychain service and the iOS background task — derives from the base one.
  An Apple ID signed in to Xcode is enough: according to Apple's capability tables, a free Apple Developer account, without the paid membership, supports App Groups, Keychain Sharing, the App Sandbox and Background Modes on macOS and iOS alike.
  What it costs is on a physical iPhone, where a free account's provisioning profile expires after about a week; the Mac and the Simulator are unaffected.
- A `Local.xcconfig` made from the earlier template — Manual signing, a `PROVISIONING_PROFILE_SPECIFIER` and `CODE_SIGN_ENTITLEMENTS` at the root — must be replaced rather than kept.
  With no target naming a profile of its own any more, those assignments now reach the widget extension and both test bundles as well, which signs them against a profile made for something else.
- **Never pick a team in a target's Signing & Capabilities tab.**
  Xcode writes the choice into `project.pbxproj` as a target-level `DEVELOPMENT_TEAM`, which overrides `Local.xcconfig` and the root alike and ends up committed.
- `Cirruscope.xcconfig` includes `Local.xcconfig` last (`#include? "Local.xcconfig"`), so what it sets overrides the root's own assignments, the team included.
  `Cirruscope/Cirruscope.xcconfig` and every per-target `.xcconfig` end with the same `#include? "Local.xcconfig"`, resolved, like every include, relative to the file making it (as `#include "../Cirruscope.xcconfig"` shows), so each of them also reads a `Local.xcconfig` in its own folder, such as `macOS/Local.xcconfig`, which the `.gitignore` entry ignores at any depth.
  Such a file is read after its folder's own assignments, so what it sets overrides them, the entitlements included, which is why it counts among the overrides above.
  Keep `Local.xcconfig` at the repository root all the same: every folder holding one of those `.xcconfig` files is synchronized, so a `Local.xcconfig` placed in it is copied into the built product of every target listing that folder, and ignoring it in git does nothing to stop that.
  The `.xcconfig` files themselves stay out of the products only because each is named in its folder's `membershipExceptions` in `project.pbxproj`, so a new `.xcconfig` in a synchronized folder needs an exception of its own.
- **To keep the developer's real store out of a run**, build or test under a base identifier of its own: `xcodebuild test … CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest -allowProvisioningUpdates`, or a contributor's own base identifier with `.citest` appended.
  Automatic signing registers that identifier and its App Group under the team, so the run gets an App Group container, a store and a Keychain service of its own, the store starting empty.
  Reach for it when a change touches the App Group, the sandbox, the live schema, or anything opened at launch.
- **Xcode Cloud is the CI that builds and tests.**
  It builds from a clean clone and signs with the tracked team and entitlements, so what it checks is the configuration that ships rather than one of its own; its manifest is `Cirruscope.xcodeproj/xcshareddata/xcodecloud/manifest.json`.
  Building in Release, whose whole-module optimization can fail where a Debug build succeeds, is its job too.
  The GitHub workflows compile nothing — `swiftformat.yml` runs on `macos-26`, which ships SwiftFormat, and the rest on `ubuntu-latest` — so a pull request from a fork gets no automatic build or test on GitHub, and the maintainer runs Xcode Cloud on it before merging; that is the trade-off accepted for a CI that signs like the shipping build.
- **If a build fails while signing**, the cause is the machine's signing setup, not the checked-in configuration.
  The usual ones are no Apple ID in Xcode's Accounts settings, an `xcodebuild` without `-allowProvisioningUpdates`, no `Local.xcconfig` on a machine whose Apple ID is not on the maintainer's team, or a `Local.xcconfig` naming a team that Apple ID is not a member of, a base identifier another team has registered, or the earlier template's assignments.
  Fix it there — never by taking the team or the entitlements out of `Cirruscope.xcconfig`, `Cirruscope/Cirruscope.xcconfig` or `Widgets/Widgets.xcconfig`, or by signing ad-hoc, which produces exactly the build that traps at launch.

## Testing

The `macOSTests` target holds unit tests written with **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.
It is hosted by the app (`TEST_HOST`/`BUNDLE_LOADER`), so tests reach the app's internal types through `@testable import Cirruscope` and may touch AppKit directly.
`Cirruscope for macOS.xcscheme` and `Cirruscope for iOS.xcscheme` are both committed in `Cirruscope.xcodeproj/xcshareddata/xcschemes/`, so each scheme's test action is the same everywhere rather than depending on the per-user schemes Xcode autocreates (`xcuserdata` is gitignored).

```bash
xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for macOS' -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
```

`iOSTests` holds the suites for what only iOS does, written with Swift Testing and hosted by the iOS app in the same way: the web view's insets and its user agent in `iOSTests/WebView/`, and the background refresh's property-list configuration in `iOSTests/Notifications/`.
A suite covering shared code goes in `Tests/`, which both test targets list, so it runs against both app modules rather than one.
That is not redundancy: `Core/` and `Cirruscope/` are compiled twice, against two SDKs, and a framework can answer differently on each — the very thing a suite pinned to one platform cannot see.
Both targets have a test action; run whichever the change touches, and both when it touches a shared folder.

The iOS suites run the same way, but need a *concrete* Simulator rather than the generic destination a build takes, because a test action has to run somewhere:

```bash
xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for iOS' -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -allowProvisioningUpdates
```

Substitute whatever device is installed.

Both commands carry `-allowProvisioningUpdates` because a test run signs for real like every other build, and automatic signing may register identifiers and fetch profiles from the command line only when it is allowed to — see "Building and Signing".
Never strip signing from a run, or from a build of either app, with `CODE_SIGNING_ALLOWED=NO` or an empty `CODE_SIGN_ENTITLEMENTS`: what that produces is an unentitled build, which traps at launch.

In Xcode, Product ▸ Test (⌘U) runs exactly the same suites as the scheme selected; the two commands above are what to use from a terminal session, and Xcode Cloud, the project's CI, builds and tests from the same shared schemes.
Debug is not incidental either way: `@testable import` needs the testability that the Release configuration does not enable.

**What to test.**
Swift-only logic that can be exercised without a live Nextcloud server or a web view — shortcut matching and its conflict rules, display-string rendering, DTO derivations, pure helpers and pure decision functions.
When a change adds or alters logic of that kind, add or update its tests in the same change, without being asked.

**What not to test, and why.**
The WebKit-facing half of the app — navigation handling, downloads, injected scripts, notification bridging — is not unit-tested: it needs a real server, a real `WKWebView`, and real network conditions, so tests there are slow, flaky, and assertion-poor compared with what they cost to maintain.
That behaviour is verified by hand against a live server instead (see "Retrieving logs to research a bug").
What that code decides is still tested wherever it can be pulled out into a value type that takes everything it needs as arguments, as the navigation decisions both web views share are in `Tests/WebView/`.
Do not add a test whose only assertion is that a WebKit delegate was called.

**When the code assumes something about a framework, test the framework.**
A unit test that restates an assumption cannot catch the assumption being wrong, and this project has a scar to prove it: the shortcut comparison was built on a documented-sounding but false claim about which modifier bits AppKit matches key equivalents against.
`KeyEquivalentProbe` therefore drives real `NSMenu.performKeyEquivalent(with:)`, and `KeyEquivalentMatchingOracleTests` asserts that `ShortcutMatching.areEquivalent(_:_:)` agrees with it for every pair of a shared fixture corpus.
Prefer that shape — measure the framework, then assert the app agrees — over encoding a belief twice.

**Conventions.**

- Tests live in a subfolder named after the feature domain they cover (`KeyboardShortcuts/`, `WebView/`, `Icons/`), never loose at a target's root, so the targets stay navigable as domains accumulate.
  Which root that subfolder sits under follows the code under test rather than the folder it happens to live in: `Tests/` when the code is shared — anything in `Core/` or `Cirruscope/` — and `macOSTests/` or `iOSTests/` when it is that platform's alone.
  Name the folder after the domain rather than after the app source folder, since one domain's logic is typically spread across several of those.
  Every one of these groups is file-system synchronized, so a new subfolder needs no project-file change — creating it is enough.
- The same one-type-per-file and documentation rules as the app's source apply to test files: a suite is a type, so it gets its own file and a documentation comment explaining what it covers and why the suite exists at all.
- Share fixtures through a named type (`ShortcutFixture`) instead of copying a corpus between suites, so two suites cannot silently drift apart on what they cover, and use `@Test(arguments:)` for matrices rather than hand-unrolled cases.
- Annotate a suite `@MainActor` when it touches AppKit (`NSMenu`, view types), and add `.serialized` where cases would otherwise contend for the main actor.
- Never let a case post a notification the host app observes.
  The app runs for the whole test run, a restored web window included, so the post reaches its real observers — and `NotificationCenter` runs an observer synchronously on the posting thread, so a main-actor observer reached from a suite Swift Testing runs off the main thread traps the host and fails every case scheduled after it as a crash.
  Inject the post as a closure defaulting to the production one, and have the case count calls instead, as `AccountStore.notifyChange` and `NextcloudHeaderHeight.record(_:key:notifyChange:)` do; isolating the poster to the main actor as well, as the latter is, turns a call from a suite off the main thread into a compile error rather than a crash.
- SwiftFormat rewrites `@Test("A display name")` into a backtick-quoted function name (`func \`A display name\`()`).
  That is the project's configured style — write the sentence, run `swiftformat .`, and leave the result alone.
- Tests must not contribute localized strings: `macOSTests/macOSTests.xcconfig` and `iOSTests/iOSTests.xcconfig` set `SWIFT_EMIT_LOC_STRINGS = NO`, so the string-catalog completeness check stays about the app's own strings.
  Never wrap a test's literal in `String(localized:comment:)`.

**Testing the account store.**
`AccountStore` takes its `ModelContainer` at initialization: `shared` passes `AppDatabase.container`, and the suites pass an in-memory one built by `AccountStoreHarness`, one harness per test case.
The store is shared, so the harness lives in `Tests/Account/` and runs against both app modules, as do the suites over it that need nothing platform-specific, filed under `Tests/` by domain; `macOSTests/Account/` holds the part that needs AppKit — the shortcut suites and `ReservedShortcuts`, which builds the reserved-shortcut stand-in out of `ShortcutMatching`.
The harness therefore takes that stand-in as a closure rather than as a list of shortcuts it compares itself.
Two rules keep that safe and must stay observed, since nothing enforces them mechanically.
Never name `AccountStore.shared` from a test — its container lives in the shared App Group container and holds the developer's real account, and `AppDatabase.container`'s recovery path moves the store files aside on a failed open and opens an empty store in their place.
Never build a second store over `AppDatabase.container` either: each instance memoizes the single `Account` and the single `DevicePreferences` separately, so two of them over one container would each believe a stale answer.

The store's two reaches outside itself are injected through its initializer as plain closures — no protocols, no mock types, no `#if DEBUG` — because the test bundle is hosted by the app, which changes what a test may assume.
`isReservedShortcut` defaults to reserving nothing, which is what the iOS app's `shared` relies on, while the Mac app's `shared` passes a wrapper around `AppDelegate.reservedShortcutName(for:)`, which answers from the live `NSApp.mainMenu`: the real menu bar is loaded for the whole test run, so a case using ⌘Z would be measuring `Main.storyboard` rather than the store.
`notifyChange` takes the name of the domain that changed and defaults to `AccountStore.post(_:)`, the production post, which is deliberately asynchronous.
`AppDelegate` observes `Notification.Name.serverAppsDidChange` and `Notification.Name.keyboardShortcutsDidChange` for the whole run, and every open `WebViewController` observes `Notification.Name.appearanceSettingsDidChange`, so a test write would otherwise have the live View menu rebuilt from `AccountStore.shared`, or a live window re-apply its appearance, on a main-queue turn no test controls; the harness counts announcements instead, which is also the only way to assert one at all.

`AccountStore.persist(serverApps:)` takes the app's own `ServerAppTransferObject`, not `Rainmaker.NavigationItem`; the mapping lives in `ServerConnection.refreshNavigationApps(using:)`.
Keep it that way — it is what lets a test seed an app list without linking Rainmaker, which neither test target does.
Note also that each host app opens a store of its own during every test run regardless (`applicationDidFinishLaunching(_:)` → `rebuildServerAppsMenu()` → `AccountStore.shared.serverApps` on macOS, `iOSApp.init()` → `Store.restored()` → `AccountStore.shared.serverApps` on iOS) — the real one in the App Group container, which on a developer's machine holds their own account unless the run was given a base identifier of its own (see "Building and Signing"); that is expected, not a regression.
What matters is that no test *writes* through it, which a run confirms by leaving the store file's modification time untouched.

**Deliberately untested in the store.**
The side effects of `disconnect()`, the one sign-out both apps run: `AssetCache.shared.clear()` deletes the developer's real cached assets, `ServerAppIcons.shared.clear()`, `ServerAvatars.shared.clear()` and `ConversationAvatars.shared.clear()` drop the app icons, avatars and conversation pictures already drawn from them, `ActivityFeedStore.clear()` deletes the widget's real saved feed, `WidgetCenter.shared.reloadAllTimelines()` makes the real widget redraw, and `Keychain.clearAll()` clears their real credentials.
Its storage half is `deleteAccount()`, and that is covered — cascade delete, memoization reset, which domains it announces, and that the device's keyboard shortcuts and appearance settings survive it.
`forgetCachesIfSignedOut()`, which empties the same caches again after a download a sign-out overtook, stays out for the same reason, and reads the real Keychain besides.
`persist(theming:)` likewise stays out: it downloads through `AssetCache.shared` into the real App Group caches directory on every call (the logo unconditionally, even when the background is a plain colour), and its `Rainmaker.Theming` input cannot be built without linking Rainmaker.
Covering the one piece of real logic in it — resolving a server-root-relative background against the account's address, and skipping that when `backgroundPlain` is set — means extracting that resolution into a pure function first; do that when it next changes rather than as a detour.

## REUSE Compliance

This project is checked for [REUSE](https://reuse.software/) Specification 3.3 compliance by `.github/workflows/reuse.yml` (`fsfe/reuse-action@v6`): every file must carry SPDX copyright and license metadata, either as an inline header or as an entry in `REUSE.toml`.

- The convention throughout the project is `SPDX-FileCopyrightText: <year> Iva Horn` and `SPDX-License-Identifier: MIT`, written as the two-line header appropriate to the file's comment syntax (`//` for Swift/JavaScript, `/* */` for CSS, `<!-- -->` for Markdown, `#` for shell-style configs like `.gitignore` and `.swiftformat`), placed at the very top of the file with a blank line before the rest of its content.
  `<year>` is the year the file was actually created — never hardcode the current year as a blanket constant, since files created in different years must carry different years, including ones added long after this instruction was written:
  ```bash
  # Year a new file is created: use the current year.
  # Year an existing file predating SPDX coverage was created: check when
  # its content first appeared, treating a delete-then-recreate at the same
  # path as a fresh creation (its year, not the original's):
  git log --follow --format=%ad --date=format:%Y -- <path> | tail -1
  ```
- Files that cannot safely hold an inline comment — binaries, pure JSON, or anything Xcode/SwiftPM/Icon Composer regenerates or rewrites through its own GUI or tooling (the asset catalog, the `AppIcon.icon` bundle, `project.pbxproj`, `contents.xcworkspacedata`, `Package.resolved`, `Main.storyboard`, `Info.plist`, `PrivacyInfo.xcprivacy`, `Localizable.xcstrings`, `.swift-version`) — are covered by a `[[annotations]]` entry in `REUSE.toml` instead.
  Add new files of these kinds to an existing matching `path` glob there only if its year already matches, or a new annotation block otherwise; never hand-edit an SPDX comment into them.
- `.github/PULL_REQUEST_TEMPLATE.md` is one exception: GitHub pre-fills a new pull request's description textarea with this file's raw, unrendered content, so an inline HTML comment header would show up as literal visible clutter for every contributor opening a PR — it is covered by a `REUSE.toml` entry instead, even though Markdown normally takes an inline header.
- `Website/` is another: a single `Website/**` annotation in `REUSE.toml` covers everything under it, which is why none of its HTML, CSS, or JavaScript carries an inline header.
- `AppStore/` is the third: every file there is pasted verbatim into App Store Connect, where a header would be published along with the text, so a single `AppStore/**` annotation covers them.
- Whenever a change adds a new file, give it SPDX coverage immediately — an inline header or a `REUSE.toml` entry — rather than leaving it for later.
- Always run `reuse lint` in the project root directory after applying changes (install via `brew install reuse` if missing), and confirm it reports "Congratulations! Your project is compliant with version 3.3 of the REUSE Specification" before considering the change complete.
- **A file can carry a correct header and still be reported as missing one.**
  `reuse` 6.2.0 failed to see the header on `Core/Collectives/CollectivePageWebRoute.swift` while the byte-identical header on its sibling was read without complaint; the trigger was a single 346-character documentation line containing two em dashes around a backtick-quoted token, and removing *either* the em dashes or the backticks made the file pass.
  It is not file size, not the leading comment block, and not the header.
  This is worth knowing because the project's own style — one sentence per line, long prose comments, em dashes and backticks throughout — produces exactly that shape routinely, and the failure surfaces as `reuse.yml` reporting a licensing problem on a file whose licensing is fine.
  If it happens, split the sentence rather than hunting for a header bug.

## Documentation Instructions

- Write Markdown prose one sentence per line: end the line after every `.`, `?` or `!` that ends a sentence, never wrap at a fixed column, and indent a list item's continuation lines to the item's text.
  A single line break inside a paragraph renders as a space, so the rendered page is unchanged, while a diff then shows only the sentences a change touched rather than the whole paragraph around it.
  This applies to every Markdown file in the repository, and it is the same principle the documentation-comment rule under "Code Style" states.
  Commit messages and pull request descriptions are the exception: GitHub shows their line breaks as written, so those stay one paragraph per line.
  The texts in `AppStore/` are not Markdown at all, and keep exactly the line breaks App Store Connect is to show.
  See `DECISIONS.md` → "Why does every sentence in the Markdown files start on its own line?".
- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check `./Website` for necessary updates in regard to localization, feature description, changes in supported target platforms, Nextcloud server releases or Nextcloud server apps.
- **The feature copy is deliberately generic, and checking it usually means confirming it still holds rather than editing it.**
  "Search directly in Spotlight for your Nextcloud content" covers whatever is indexed today and whatever is indexed next, which is the point: a sentence enumerating apps, notes, collectives and conversations would be accurate for one release and would need revisiting, in four languages, on every one after it.
  Adding a data type is therefore normally a change with no website edit in it at all.
  Where the specifics are worth publishing they belong somewhere written for that — release notes, or a page of its own — rather than in copy that has to stay true indefinitely.
  Edit these cells when a capability genuinely changes shape, not when it grows.
- **Keep the upcoming release's "What's New" current, without being asked.**
  A change a Mac user would notice — a feature, a visible fix, a change in behaviour — adds or edits a line in `AppStore/<MARKETING_VERSION>/macOS/English/WhatsNew.txt`, in the style of the published versions, and carries it into the German, French and Spanish files in the same change.
  When that version's folder does not exist yet, create it: copy `Description.txt`, `Keywords.txt` and `Subtitle.txt` of the newest version, which carry over until something changes them, and start `WhatsNew.txt` afresh.
  If `MARKETING_VERSION` names a version already tagged, it has been published and its folder is not edited; the line waits until the version is raised.
  `Description.txt` follows the rule of the website's feature copy above: it changes when a capability changes shape, not when it grows.
  Changes only iOS, a test or the documentation sees add nothing there.

## Design Decisions

`DECISIONS.md` is a technical FAQ recording *why* the project is built the way it is — its design and architecture choices and the reasoning behind each.
It complements this document, which covers *how* to work in the codebase, and is the developer-facing counterpart to the public FAQ on `./Website`.

- Whenever a change makes, changes, or reverses a non-obvious or hard-to-reverse choice — a UI framework, target platform, dependency, persistence layer, or authentication flow, or a deliberate decision *not* to build something — add or update the matching entry in `DECISIONS.md` without being asked.
- Write each entry as a plain-language `## Why …?` question followed by a short answer that explains the reasoning and the trade-off accepted, matching the FAQ style of the existing entries.
- Do not record routine implementation details or bug fixes — only choices with lasting design consequence.
  Nothing enforces this mechanically the way `reuse lint` enforces licensing; it relies on recognizing when a change embodies a decision, so err toward recording it when unsure.
- When a decision changes, edit or remove its answer rather than preserving the old text — the file is version-controlled, so its history lives in git.
- Keep the reasoning consistent wherever it also appears: if a decision is likewise explained in a Swift documentation comment, `README.md`, or elsewhere in this document, update those together, and, per "Documentation Instructions" above, check `./Website` when a decision affects the public story such as supported platforms or features.

## Localization Instructions

English is the app's base (development) language, and the project is additionally localized into a set of languages configured in the Xcode project.
Do not hardcode or assume that set — detect the enabled localizations programmatically so this workflow keeps working as languages are added or removed.

The localization stores are String Catalogs, so there are no per-locale `.lproj` resource folders to enumerate for this (only `macOS/Base.lproj`, the storyboard source, and `macOS/mul.lproj` — "multiple languages" — which holds the storyboard's catalog file itself, not a per-language folder).
The canonical, and only, source for the enabled locales is `knownRegions` in the project file; read it directly, filtering out `en` and `Base`, which are not translation targets:

```bash
plutil -convert json -o - Cirruscope.xcodeproj/project.pbxproj \
  | python3 -c 'import sys, json; d = json.load(sys.stdin); print([r for r in [o["knownRegions"] for o in d["objects"].values() if o.get("isa") == "PBXProject"][0] if r not in ("en", "Base")])'
```

Localization lives in eight String Catalogs (JSON, all with the same shape: each key maps to a `comment` plus a `localizations` dict of `<locale>: {"stringUnit": {"state": ..., "value": ...}}`), and all of them must stay complete for every detected localization:

- **Swift strings** are wrapped in `String(localized:comment:)` — never hardcoded — and backed by the `Localizable.xcstrings` of every target that compiles them, a String Catalog being a per-target resource: `macOS/Localizable.xcstrings`, `iOS/Localizable.xcstrings` or `Widgets/Localizable.xcstrings` for code only that target compiles, both app catalogs for `Cirruscope/`, and all three for `Core/`.
  Each key is the literal source string, and a string in shared code has an entry in the catalog of each target that compiles it, with the same translation in every one.
  App Intents strings (a `LocalizedStringResource` such as an intent title/description, a `@Parameter` title or `requestValueDialog`, or an entity's `DisplayRepresentation` subtitle / `TypeDisplayRepresentation`) resolve from the same `Localizable` table and so live in both app catalogs too; their keys are likewise the literal source string, but they take no `comment:` argument in code, so add the catalog comment by hand.
- **SwiftUI strings** in the iOS target are backed by `iOS/Localizable.xcstrings` — its own catalog, because a String Catalog is a per-target resource.
  SwiftUI localizes on its own: a `Text`, `Label`, `Button`, `TextField` or `Link` title is a `LocalizedStringKey`, so it is written as a plain literal — `Text("Connect")`, never `Text(String(localized: "Connect"))` — and the catalog key is that literal.
  The `String(localized:comment:)` rule above governs strings the code passes around itself, not these.
  A `Label`, `Button`, `TextField` or `Link` title takes no `comment:` argument at the call site, so add the catalog comment by hand, as with App Intents strings; a `Text` can carry one through `Text(_:tableName:bundle:comment:)`, and a comment written there is extracted with its key.
  Anything that must *not* be translated takes the `verbatim:` initializer — `Text(verbatim: "Cirruscope")` for the brand name, likewise for URLs and placeholder examples — which keeps it out of the extracted keys rather than leaving a catalog entry whose translations are all identical to English.
- **Widget extension strings** are backed by `Widgets/Localizable.xcstrings`, again its own catalog because a String Catalog is a per-target resource.
  The same SwiftUI rule applies to the views, and a `WidgetConfiguration`'s `configurationDisplayName(_:)` and `description(_:)` — the name and blurb the widget gallery shows — are each given a `Text` built from a literal and its `comment:`, so they are extracted here too, comment included.
  Two habits matter more here than elsewhere.
  Anything the *server* names — a filename, a display name — must reach a `Text` as a `Text`, never interpolated into a `LocalizedStringKey`, which is parsed as Markdown along with whatever goes into it: a file called `_draft_.md` renders as `draft.md` otherwise, silently.
  And a word the design shows in capitals is written here in sentence case with `.textCase(.uppercase)` applied at the view, so each language's own uppercasing applies to its own word rather than to an English one.
- **Storyboard strings** in `macOS/Base.lproj/Main.storyboard` are backed by `macOS/mul.lproj/Main.xcstrings` (migrated off the old per-locale `Main.strings` files — do not reintroduce those).
  Each key is `<objectID>.<property>`, e.g. `"5xm-BD-bvl.title"`, and the `comment` field still carries the generated `Class = …; title = …; ObjectID = …;` context Xcode always regenerates from the storyboard's current content.
- **Info.plist strings** — the usage descriptions each app shows in its permission prompts, plus the bundle name and the copyright notice — are backed by `macOS/InfoPlist.xcstrings` and `iOS/InfoPlist.xcstrings`, one per app target, and the two carry the same reasons with the same translations.
  Here each key is the property-list key name (e.g. `NSCameraUsageDescription`), *not* the English text, so unlike the three `Localizable` catalogs these carry an explicit `en` `stringUnit` as well.
  A usage description's English source of truth is the matching `INFOPLIST_KEY_*` build setting on the app target, set identically in both the Debug and Release configuration: change one and mirror it in the catalog's `en` value, in the other configuration, and, for a reason both apps give, in the other app's target and catalog.
  `CFBundleName` and `NSHumanReadableCopyright` are marked Do Not Translate, and their English values come from the xcconfig files rather than the target: the first is `PRODUCT_NAME`, which `Cirruscope/Cirruscope.xcconfig` sets to `CIRRUSCOPE_BUNDLE_NAME`, and the second is `INFOPLIST_KEY_NSHumanReadableCopyright` in the root `Cirruscope.xcconfig`, which the iOS target restates in its own build settings.
  These prompts name no brand — neither the "Nextcloud" trademark nor "Cirruscope" — and describe the capability generically instead ("during video calls", not "during Nextcloud Talk calls").
  That restriction is specific to these prompts: `Localizable.xcstrings` deliberately names both where the message is *about* the server product, as in "Cirruscope requires Nextcloud server version %lld or later."
- **App Shortcut phrases** declared in `ServerAppShortcuts` are backed by `macOS/AppShortcuts.xcstrings` and `iOS/AppShortcuts.xcstrings` (the `AppShortcuts` table Xcode extracts from the `AppShortcutsProvider`, once for each app target compiling it), and the two carry the same phrases with the same translations.
  Xcode collapses every phrase variation into a single key whose localizations are a `stringSet` — a list of `values` rather than one `value` — so a translation must supply the whole set, one entry per source phrase and in the same order.
  Each phrase's `${applicationName}` and `${target}` placeholders must be preserved verbatim, and every phrase must contain `${applicationName}`.

In all eight catalogs, a `stringUnit`'s — or, for App Shortcut phrases, a `stringSet`'s — `state` is the completeness/staleness signal Xcode itself tracks: a freshly added or changed source string starts at `"new"` for each locale and only reaches `"translated"` once a value is filled in, and Xcode flags a locale for re-review on its own when the source text changes later.
**`state` alone is necessary but not sufficient, though** — proven the hard way: migrating off the old per-locale `Main.strings` files carried every existing value straight into the catalog and marked it `"translated"` per locale, even for the ~130 entries that were never actually translated and were just sitting there as English text.
So also compare each locale's value against the `en` value, and treat a match as a real gap *unless* the key is a deliberately English/unchanged case — the brand name (`Cirruscope`), a placeholder example URL, a storyboard object whose text is fully overwritten at runtime and never shown (see the placeholder-skipping rule below), or a genuine cognate where that language's correct word simply is spelled the same (e.g. French `Services`/`Format`/`Ligatures`, German `Text`, Spanish `General` are all correct translations, not oversights):

```bash
plutil -convert json -o - Cirruscope.xcodeproj/project.pbxproj | python3 -c '
import json, sys

pbxproj = json.load(sys.stdin)
known_regions = next(o["knownRegions"] for o in pbxproj["objects"].values() if o.get("isa") == "PBXProject")
locales = [r for r in known_regions if r not in ("en", "Base")]

for catalog in ["macOS/Localizable.xcstrings", "macOS/mul.lproj/Main.xcstrings", "macOS/InfoPlist.xcstrings", "macOS/AppShortcuts.xcstrings", "iOS/Localizable.xcstrings", "iOS/InfoPlist.xcstrings", "iOS/AppShortcuts.xcstrings", "Widgets/Localizable.xcstrings"]:
    data = json.load(open(catalog))
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue  # e.g. a pure format passthrough like "%@", marked as Do Not Translate
        localizations = entry.get("localizations", {})
        # InfoPlist and the storyboard catalog carry an explicit `en` unit; in the three Localizable catalogs the
        # English source *is* the key, so fall back to it — otherwise the identical-to-English check below is
        # silently skipped for exactly the catalogs most likely to gain new strings.
        en_value = localizations.get("en", {}).get("stringUnit", {}).get("value") or key
        for locale in locales:
            loc = localizations.get(locale, {})
            # App Shortcut phrases localize as a `stringSet` (a set of spoken variations) rather than a single
            # `stringUnit`, and a numeric format (e.g. `numericFormat` on an entity type) as plural `variations`.
            unit = loc.get("stringUnit") or loc.get("stringSet") or {}
            if not unit:
                plural = loc.get("variations", {}).get("plural", {})
                units = [v.get("stringUnit", {}) for v in plural.values()]
                if units and all(u.get("state") == "translated" for u in units):
                    continue  # every plural category is translated
                unit = units[0] if units else {}
            state, value = unit.get("state"), unit.get("value")
            if state != "translated":
                print(f"{catalog}: {key!r} [{locale}] state={state!r}")
            elif value is not None and en_value is not None and value == en_value:
                print(f"{catalog}: {key!r} [{locale}] still identical to English: {value!r} (confirm this is a deliberate exception, not a missed translation)")
'
```

Run this after applying any change, not only when you believe you recognize that a user-facing string was added, renamed, or removed — that recognition is exactly what failed before this project migrated off per-locale `Main.strings` files (a storyboard menu item's title was renamed without updating its stale, plain-text translations, and it shipped unnoticed for several changes).
It is a mechanical safety net, not a substitute for judgement: a clean run only rules out the two failure modes above — it cannot tell you whether an existing translation reads *well*, so still apply the checklist below by hand for every string you touch, and use judgement on every "still identical to English" hit rather than mechanically translating deliberate exceptions.

Whenever a change adds, renames, or removes a user-facing string — in Swift, in the storyboard, or in an `INFOPLIST_KEY_*` usage description — check and update every catalog without being asked, so no localization is left behind:

- Add an entry for every new user-facing string, translated into each detected localization, to the relevant catalog.
  Keep the English source wording on the storyboard's Base object and as the `Localizable.xcstrings` key.
- Remove or rename entries whose source strings were deleted or changed, so no stale or orphaned keys remain and no localization is missing a key another one has.
- Only translate strings the user actually sees.
  Skip storyboard placeholders that are replaced at runtime (a label bound to an outlet and assigned in code, such as a cell's file-name field) and image-only button titles that are never displayed, unless the title also serves as the control's accessibility label.
- Match the established scope: the standard AppKit menu titles Xcode emits into the storyboard catalog are left untranslated by convention, so do not translate every entry — only the app's own user-facing strings.
- Never localize developer-facing text: `os` log messages stay in English (see "Logging and Diagnostics").
- Confirm both apps still build so every string catalog compiles.

### App Store texts

The texts in `AppStore/` (see "Repository Structure") are localized outside the String Catalogs and outside `knownRegions`.
Their languages are App Store Connect's localizations of the app — English, German, French and Spanish — which match the app's own today but are a list of their own.

- English is the source of truth.
  Every other language is translated from it rather than written on its own, and a change to an English file is carried into the same file of every other language in the same change.
- Every language folder of a version holds the same set of files as its `English/` folder.
- They address the reader informally — "du" in German, "tu" in French, "tú" in Spanish — as the website does, even though the app's own strings say "Sie" and "vous".
  A UI label they quote is still the app's own localized label, word for word, as is a system label Apple's localization of macOS shows.
  The published 1.1.0 French texts predate this rule and say "vous"; being published, they stay as they are.
- Name every macOS feature by Apple's own term in that language — Mitteilungszentrale, centre de notifications, Centro de notificaciones — rather than the website's, which is wrong in places.
  Write the Spanish for Spain in a way that also reads naturally in Latin America, since those storefronts show the same text.
- A translation runs longer than its English, so an English text close to its field's limit leaves the translations no room; keep the English well below it.
- No emoji, however well it would fit: App Store Connect rejects a text containing one as having an invalid character.

Check every file against its field's limit, and every language against English, after any change to `AppStore/`:

```bash
python3 - <<'EOF'
import pathlib
import re
import sys

limits = {"Description.txt": 4000, "WhatsNew.txt": 4000, "WhatToTest.txt": 4000, "Keywords.txt": 100, "Subtitle.txt": 30}
emoji = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]")
problems = []

for platform in sorted(p for p in pathlib.Path("AppStore").glob("*/*") if p.is_dir()):
    english = {f.name for f in (platform / "English").glob("*.txt")}
    for language in sorted(p for p in platform.iterdir() if p.is_dir()):
        names = {f.name for f in language.glob("*.txt")}
        if names != english:
            problems.append(f"{language}: missing {sorted(english - names)}, extra {sorted(names - english)} compared with English")
        for file in sorted(language.glob("*.txt")):
            text = file.read_text()
            length = len(text.removesuffix("\n"))
            if file.name not in limits:
                problems.append(f"{file}: not a field this project records")
            elif length > limits[file.name]:
                problems.append(f"{file}: {length} characters, over the limit of {limits[file.name]}")
            if not text.endswith("\n") or text.endswith("\n\n"):
                problems.append(f"{file}: must end with exactly one newline")
            if emoji.search(text):
                problems.append(f"{file}: contains an emoji, which App Store Connect rejects")

if problems:
    sys.exit("\n".join(problems))
EOF
```

## Concurrency

Cirruscope builds with `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (both in `Cirruscope.xcconfig`, the latter stated explicitly so a target-level override shows up in a `-showBuildSettings` diff — Xcode's iOS target template writes `MainActor` there), so nothing in either app module is `@MainActor` unless the SDK or the code says so explicitly — there is no implicit "everything defaults to the main actor" convenience to lean on.

- Types that subclass `NSResponder` — `NSViewController`, `NSWindowController`, `NSView` (and their subclasses like `NSTableCellView`) — already inherit `@MainActor` from the SDK itself (`NS_SWIFT_UI_ACTOR` is annotated on `NSResponder`), so they need no annotation of their own.
- Plain `NSObject` subclasses (with no `NSResponder` in their hierarchy) get no such inheritance: annotate the type `@MainActor` explicitly whenever it touches AppKit/WebKit state that requires it, as `AppDelegate` and `DownloadManager` do.
- A closure handed to a system completion-handler or callback API is only guaranteed to run on the main actor if that API's closure *parameter type* itself is annotated `@MainActor` by the SDK (e.g. `WKNavigationDelegate`'s decision handlers).
  When it isn't (e.g. `ASWebAuthenticationSession`'s completion handler, `NSEvent.addLocalMonitorForEvents`'s handler, KVO change handlers), never assume the calling thread.
- **A closure written directly inside a method of a main-actor type is itself inferred main-actor-isolated, purely from being lexically nested there — regardless of what its body does.**
  Wrapping the body in `Task { @MainActor in ... }` does *not* fix this: the compiler still inserts a dynamic isolation check at the *outer* closure's own entry point (the same mechanism as `MainActor.assumeIsolated`), and that check traps the instant the framework invokes the closure off-main, before the inner `Task` ever runs — this crashed Cirruscope in production despite the inner hop being "correct" in isolation.
  The actual fix is to form the closure inside a `nonisolated` factory method (returning the closure), so there is no enclosing main-actor context for the compiler to infer from, and to explicitly hop with `Task { @MainActor in ... }` *inside* that nonisolated closure — see `LoginSession.makeAuthenticationCompletionHandler()` and `ShortcutRecorderView.makeKeyDownHandler()`.
  Only pass `Sendable` values across that hop (e.g. a KVO change's `.newValue`, or a `UUID` identity, per `DownloadTableCellView`'s KVO handler) — the source object itself (an `NSEvent`, a `WKWebView`) is usually not `Sendable` and must not be captured into the `Task`.
- **The counterpart test, and the reason a `@Sendable` callback needs none of that:** a closure whose *contextual type* is `@Sendable` does not inherit the isolation it is written in, so no dynamic check is emitted and the bullet above does not apply to it.
  That is the whole question to ask of any framework callback — is the closure parameter type `@Sendable`?
  `ASWebAuthenticationSession`'s completion handler is a bare `(URL?, (any Error)?) -> Void` and is not, which is why it needed a `nonisolated` factory.
  SwiftUI's `backgroundTask(_:action:)` types its action `@escaping @Sendable (D) async -> R` and is, which is why `iOSApp` can write the background refresh inline in `body` — main-actor-isolated by the SDK — and still be invoked off-main safely.
  Prefer the `async` variant of a system API wherever one exists, since a closure that never has to be written is a closure whose isolation cannot be got wrong: the iOS notification badge reaches `UNUserNotificationCenter` and `BGTaskScheduler` without a single completion handler.
- `UserNotifier`'s `nonisolated` delegate methods are a variant of the same pattern worth following directly: the *method* is marked `nonisolated` (rather than a closure built by a `nonisolated` factory), so it is never inferred main-actor no matter which type it's declared on, and it hops via `Task { @MainActor in ... }` internally.

## Logging and Diagnostics

Cirruscope logs through `os.Logger` (see `Core/Logging.swift`).
Every behavioural type owns a logger that `Logger(for:)` builds from its own type — the subsystem is the running bundle's identifier and the category is the type name.
That subsystem is `de.i2h3.cirruscope` in both apps and `de.i2h3.cirruscope.widgets` in the widget extension, `Core/` code included when the extension runs it, which is why the predicates below match the shared prefix with `BEGINSWITH` rather than one subsystem with `==`.
Passive types — the `@Model` records, the transfer objects, the routes — have no logger, with the two exceptions named under "Adding logging to new code".

**There are no signposts.**
Nothing in the code emits one, and `Core/Logging.swift` has no `OSSignposter(for:)` counterpart to `Logger(for:)`.
If intervals are wanted, add them deliberately, that initializer included; `log show` lists signposts only when it is passed `--signpost`.

### Retrieving logs to research a bug

Use `log show` to read logs already recorded in a past time range, and `log stream` to watch them live.
**Invoke the tool as `/usr/bin/log`**: zsh's builtin `log` otherwise shadows it and fails with "too many arguments".

```bash
# Everything Cirruscope logged in the last 30 minutes, machine-readable:
/usr/bin/log show --last 30m --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope"' --style ndjson

# A specific window of time (device-local clock):
/usr/bin/log show --start "2026-07-06 14:00:00" --end "2026-07-06 14:10:00" --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope"' --style ndjson

# One category (type) only — e.g. the download coordinator:
/usr/bin/log show --last 1h --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope" && category == "DownloadManager"' --style ndjson

# Watch live while reproducing a bug:
/usr/bin/log stream --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope"' --level debug --style ndjson
```

**`log show` reads this Mac's store, not a phone's.**
Nothing the app does on an iPhone reaches this Mac's log, whether it happened in the foreground with Xcode attached or in a background refresh with nobody watching, so the record has to be pulled over first: `sudo /usr/bin/log collect --device-name "<name>" --last 24h --output ~/Desktop/cirruscope.logarchive`, then `log show <archive> --predicate ...` against that.
In the Simulator each device keeps a store of its own, which the host's `log show` does not read either: run the commands above inside it through `xcrun simctl spawn booted`, as in `xcrun simctl spawn booted log show --last 30m --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope"' --style ndjson`.
Do not pass `--info` or `--debug` to `log show`: neither level is persisted, so they only imply a completeness the output does not have — those levels are captured live, with `log stream --level debug`.

Two more reasons a capture can look emptier than the code suggests, both worth ruling out before concluding a line is missing.
Console.app hides `.debug` and `.info` until Action ▸ Include Info/Debug Messages is switched on, which is most of the entry and exit lines.
And every dynamic value without an explicit `privacy: .public` reads as `<private>` on a device with no logging configuration profile installed — so a line that is present can still say nothing.

- Only `.notice`, `.error`, and `.fault` are persisted to the store, so those are what `log show --last`/`--start` reliably returns after the fact; `.debug` and `.info` are ephemeral and appear only while `log stream` (or Instruments) is actively capturing.
  Put anything worth retrieving later at `.notice` or higher.
- Dynamic values are redacted as `<private>` unless the app runs from Xcode or a logging configuration profile that enables private data for the subsystem is installed; the repository does not ship one.

### Adding logging to new code

- Give each new behavioural type its own logger, naming the type itself, as in `private let logger = Logger(for: ServerAddressViewController.self)`: a class cannot refer to `Self` in a stored property's initializer.
  Do not add loggers to passive types, with two exceptions made deliberately, both values whose failure would otherwise leave no trace.
  `SameOriginURL` has one because its `nil` is the app refusing to send the user's app password somewhere, and a refusal nobody can see is indistinguishable from a typo.
  `WebAccentColor` has one because its failable initializer is the only sign that an accent color could not be expressed in sRGB, which leaves the page on Nextcloud's own primary color.
- **Identifiers, counts and the branch taken are `privacy: .public`; what the user wrote is not.**
  A note's identifier, a conversation's token, a collective's id, how many of something was fetched or pruned, which guard refused and why — all in the clear, because a capture that cannot say what happened is not a capture.
  Note titles, conversation names and page titles keep `os_log`'s default redaction: they are somebody's private data, and the unified log is collected by sysdiagnose and shared with Apple and with support.
  `error.localizedDescription` is `.public`, since an error hidden in the failure case is the one worth reading.
- **Log the whole of a path, not only its ends.**
  The fetch layer and the App Intents layer were well covered while the store between them logged nothing at all, and the result was a refresh that could be seen starting and seen donating with no way to tell what it had stored.
  A domain's story should read end to end under one `log stream`: fetched *n*, persisted *n* inserted / *n* updated / *n* pruned, announced, donated *n*.
- `import os` in every file that *calls* a logger — including extension files — because member-import visibility is enabled.
- Make the logger `internal` (drop `private`) when the type's extensions in other files log through it — `ServerConnection` and `AccountStore` both do, so that both halves of one operation read as one story — `nonisolated let` when `nonisolated` callbacks log through it, and `private static let` on the namespace enums.
- Keep the category equal to the type name.
  To tell apart several live instances of one type, give it an auto-incremented `UInt64` identifier (see `WebViewController.logID` and `nextLogID`) and append it to each message in parentheses as `(TypeName \(id))`, e.g. `(WebViewController 3)`, rather than encoding identity in the category.
  Integers print in the clear (a `String` id would be redacted), while secrets and personal data stay at the default private redaction.
- In the delegate-heavy WebKit and download files, log every method's entry and every return or early exit at debug level with the reason, so navigation and transfer behaviour can be reconstructed from a capture later.

## Commit Instructions

- Do not commit automatically.
- Suggest commit title after applying changes.
  If the changes relate to specific GitHub issues, mention them.
- Suggest commit description after applying changes.
- Every commit must carry a `Signed-off-by:` trailer per this project's [Developer Certificate of Origin](./CONTRIBUTING.md#developer-certificate-of-origin) policy, matching the git identity of whoever is being committed on behalf of in the current session (`git config user.name`/`user.email` — never a hardcoded name, since a different contributor's session must sign off as themselves), in addition to any `Co-Authored-By:` trailer already appended.

## Pull Request Instructions

- Do not open a pull request automatically.
