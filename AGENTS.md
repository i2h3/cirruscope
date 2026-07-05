#  AGENTS.md

You are an experienced software engineer specialized on native apps for macOS written in Swift using AppKit.

## Repository Structure

- `Framecloud/` contains the Swift source code, resources, and configuration for the app target.
    - `AppDelegate/` contains `AppDelegate.swift`, the application delegate that owns the web windows and builds the server-app items in the View and Dock menus, and its window-restoration and provide-feedback extensions.
    - `Web/` contains `WebViewController` with its `WKNavigationDelegate`, `WKUIDelegate`, and menu-validation extensions, the `WebWindow`/`WebWindowController` that host it, and `WebViewScript.swift`, which enumerates the bundled JavaScript resources and loads their source from the bundle on demand.
    - `Downloads/` contains the download feature: `DownloadManager.swift` is the `WKDownloadDelegate` facility that coordinates every transfer decoupled from the UI, `DownloadManager+WKDownloadDelegate.swift` is its delegate conformance, `Download.swift` is the runtime model of a single transfer, and `DownloadViewController` with its table data-source and delegate extensions and `DownloadTableCellView` presents the download history.
    - `Settings/` contains `Settings.swift`, which defines the app's persisted settings, the general and server-apps settings view controllers with their table extensions, and `ShortcutRecorderView`.
    - `ServerAddress/` contains `ServerAddressViewController` with its text-field-delegate and web-authentication extensions used to sign in.
    - `Views/` contains custom views shared across features, such as `BackgroundImageView`.
    - `Models/` contains the shared model types: `Credentials` (the login name and app password from Login Flow v2), `FramecloudError` (the shared error type thrown by app-level facilities), `KeyboardShortcut` (a user-assigned shortcut for a server app), and `ServerApp` (a persisted Nextcloud server app shown in the menus and settings).
    - `AssetCache.swift` manages on-disk copies of remote assets in the app's caches directory.
    - `Keychain.swift` stores the Login Flow v2 credentials in the macOS Keychain.
    - `Logging.swift` adds the `Logger(for:)` and `OSSignposter(for:)` convenience initializers that every behavioural type uses to build its own `os` logger and signposter under the app's bundle-identifier subsystem, categorized by type name.
    - `ServerConnection.swift` builds and validates `Rainmaker.Server` instances and fetches the server apps.
    - `UserNotifier.swift` presents notifications from the web interface, and download-completion notifications from `DownloadManager`, in the macOS Notification Center.
    - `Assets.xcassets` contains image and color assets.
    - `AppIcon.icon` is the app icon bundle.
    - `Base.lproj/Main.storyboard` defines the app's user interface, and `de.lproj`, `fr.lproj`, and `es.lproj` hold its German, French, and Spanish localizations.
    - `Framecloud.css` is the stylesheet injected into the web view.
    - `Scripts/` contains the JavaScript resources injected into or evaluated within the web view.
    - `Info.plist` is the app's information property list, and `PrivacyInfo.xcprivacy` is its privacy manifest.
- `Frameworks/` contains the bundled frameworks the app links against.
- `Products/` contains the built app bundle.

## Code Style

- This project is set up to use SwiftFormat.
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Never wrap arguments in func declarations or calls.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check the "Features" section of `./README.md` for validity and update, if necessary.

## Localization Instructions

English is the app's base (development) language, and the project is additionally localized into a set of languages configured in the Xcode project. Do not hardcode or assume that set — detect the enabled localizations programmatically so this workflow keeps working as languages are added or removed.

```bash
# The project's localizations to translate into — every localized `.lproj` folder except the base:
ls -d Framecloud/*.lproj | sed -E 's#.*/##; s/\.lproj$//' | grep -vx Base
```

Those `.lproj` folders are the resource directories that actually hold the localized `Main.strings`, so this list is what you edit. The canonical project registry is `knownRegions` in the project file; read it directly if you need the authoritative setting, remembering it also includes the base region and `Base`, which are not translation targets:

```bash
plutil -convert json -o - Framecloud.xcodeproj/project.pbxproj \
  | python3 -c 'import sys, json; d = json.load(sys.stdin); print([o["knownRegions"] for o in d["objects"].values() if o.get("isa") == "PBXProject"][0])'
```

Localization lives in two stores, and both must stay complete for every detected localization:

- **Swift strings** are wrapped in `String(localized:comment:)` — never hardcoded — and backed by `Framecloud/Localizable.xcstrings`. Each key carries a `comment` describing where it appears and a `translated` `stringUnit` for every localization.
- **Storyboard strings** in `Framecloud/Base.lproj/Main.storyboard` are localized through the per-locale `Main.strings` file in each `<locale>.lproj`, keyed by object ID and property and preceded by the generated `/* Class = …; title = …; ObjectID = …; */` comment, e.g. `"5xm-BD-bvl.title" = "Downloads";`.

Whenever a change adds, renames, or removes a user-facing string — in Swift or in the storyboard — automatically check and update both stores without being asked, so no localization is left behind:

- Add an entry for every new user-facing string, translated into each detected localization, to `Localizable.xcstrings` (for Swift) or to every `<locale>.lproj/Main.strings` (for the storyboard). Keep the English source wording on the storyboard's Base object and as the `Localizable.xcstrings` key.
- Remove or rename entries whose source strings were deleted or changed, so no stale or orphaned keys remain and no localization is missing a key another one has.
- Only translate strings the user actually sees. Skip storyboard placeholders that are replaced at runtime (a label bound to an outlet and assigned in code, such as a cell's file-name field) and image-only button titles that are never displayed, unless the title also serves as the control's accessibility label.
- Match the established scope: the standard AppKit menu titles Xcode emits into `Main.strings` are left untranslated by convention, so do not translate the whole file — only the app's own user-facing strings.
- Never localize developer-facing text: `os` log and signpost messages stay in English (see "Logging and Diagnostics").
- Validate the result with `plutil -lint` on each localization's `Main.strings`, and confirm the app still builds so the storyboard and the string catalog compile.

## Logging and Diagnostics

Framecloud logs through `os.Logger` and `OSSignposter` (see `Logging.swift`). Every behavioural type owns a `Logger(for: Self.self)` — the subsystem is the bundle identifier `de.i2h3.framecloud` and the category is the type name — and the asynchronous facilities also own an `OSSignposter(for: Self.self)`. The passive `Models/` types have no logger.

### Retrieving logs to research a bug

Use `log show` to read logs already recorded in a past time range, and `log stream` to watch them live. **Invoke the tool as `/usr/bin/log`**: a shell function named `log` from the user profile otherwise shadows it and fails with "too many arguments".

```bash
# Everything Framecloud logged in the last 30 minutes, machine-readable:
/usr/bin/log show --last 30m --predicate 'subsystem == "de.i2h3.framecloud"' --info --debug --style ndjson

# A specific window of time (device-local clock):
/usr/bin/log show --start "2026-07-06 14:00:00" --end "2026-07-06 14:10:00" --predicate 'subsystem == "de.i2h3.framecloud"' --info --debug --style ndjson

# One category (type) only — e.g. the download coordinator:
/usr/bin/log show --last 1h --predicate 'subsystem == "de.i2h3.framecloud" && category == "DownloadManager"' --info --debug --style ndjson

# Watch live while reproducing a bug:
/usr/bin/log stream --predicate 'subsystem == "de.i2h3.framecloud"' --level debug --style ndjson
```

- Only `.notice`, `.error`, and `.fault` are persisted to the store, so those are what `log show --last`/`--start` reliably returns after the fact; `.debug` and `.info` are ephemeral and appear only while `log stream` (or Instruments) is actively capturing. Put anything worth retrieving later at `.notice` or higher.
- Dynamic values are redacted as `<private>` unless the app runs from Xcode or a logging profile is installed — see the "Logging" section of `./README.md` for a ready-to-use profile.
- Signpost intervals (`InitialLoad`, `Validate`, `Login`, `Download`, `CacheAsset`, `LaunchValidation`) are best viewed by recording the app in Instruments with the *os_signpost* / *Points of Interest* instrument; they are only emitted while such a recorder is active.

### Adding logging to new code

- Give each new behavioural type its own `let logger = Logger(for: Self.self)` (and `OSSignposter(for: Self.self)` for asynchronous or long-running work). Do not add loggers to passive `Models/` types.
- `import os` in every file that *calls* a logger or signposter — including extension files — because member-import visibility is enabled.
- Make the logger/signposter `internal` (drop `private`) when the type's extensions in other files log through it, `nonisolated let` when `nonisolated` callbacks log through it, and `private static let` on the namespace enums.
- Signpost interval names are `StaticString` literals; use a unique `OSSignpostID` (`makeSignpostID(from:)` or `makeSignpostID()`) per concurrent interval, and store the `OSSignpostIntervalState` (for example on the model) when an interval spans separate callbacks.
- Keep the category equal to the type name. To tell apart several live instances of one type, give it an auto-incremented `UInt64` identifier (see `WebViewController.logID` and `nextLogID`) and append it to each message in parentheses as `(TypeName \(id))`, e.g. `(WebViewController 3)`, rather than encoding identity in the category. Integers print in the clear (a `String` id would be redacted), while secrets and personal data stay at the default private redaction.
- In the delegate-heavy WebKit and download files, log every method's entry and every return or early exit at debug level with the reason, so navigation and transfer behaviour can be reconstructed from a capture later.

## Commit Instructions

- Do not commit automatically.
- Suggest commit title after applying changes. If the changes relate to specific GitHub issues, mention them.
- Suggest commit description after applying changes.

## Pull Request Instructions

- Do not open a pull request automaticallx.
- Always run `swift package plugin --allow-writing-to-package-directory swiftformat --verbose --cache ignore` before committing.
