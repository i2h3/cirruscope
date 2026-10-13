<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Localization Instructions

This is the reference behind the rules in [AGENTS.md → Localization Instructions](../AGENTS.md#localization-instructions) and [AGENTS.md → App Store texts](../AGENTS.md#app-store-texts), which it does not restate.

## Where the languages come from

English is the app's base (development) language.
The canonical, and only, source for the others is `knownRegions` on the `PBXProject` object in `Cirruscope.xcodeproj/project.pbxproj`, which Xcode writes when a localization is added to or removed from the project.
It also lists `en` and `Base`, which are filtered out because neither is a translation target.
`python3 Tools/check-string-catalogs.py --list-locales` prints what remains, and the catalog check reads the same list, so neither changes when a language does.

The localization stores are String Catalogs, so the repository has no per-locale `.lproj` resource folders to enumerate.
The only two are `macOS/Base.lproj`, the storyboard source, and `macOS/mul.lproj` ("multiple languages"), which holds the storyboard's catalog file itself rather than one language's strings.
Per-language `.lproj` folders exist only in the built products, compiled from the catalogs, which is where [`ShortcutsNameTests`](../Tests/AppIntents/ShortcutsNameTests.swift) looks a translation up, the way the system resolves it.

Adding a language reaches beyond `knownRegions`:

- Until it is translated, the catalog check reports every key of all eight catalogs not marked Do Not Translate in it with `state=None`, the locale having no entry yet.
- The voice and terminology rules in AGENTS.md → Localization Instructions name the pronoun and Apple's compound term for a keyboard shortcut per language, so a new language needs its own there.
- The App Store texts are a list of their own (see [App Store texts](#app-store-texts)): a new app localization adds no `AppStore/` language folder, and the reverse holds too.
- The website has its own translations in `Website/de/`, `Website/es/` and `Website/fr/`, which [AGENTS.md → Documentation Instructions](../AGENTS.md#documentation-instructions) asks to be checked.

## The eight catalogs

| Catalog | Backs | Key |
|---|---|---|
| `macOS/Localizable.xcstrings`, `iOS/Localizable.xcstrings`, `Widgets/Localizable.xcstrings` | Swift, SwiftUI and App Intents strings of the target compiling them | the literal source string |
| `macOS/mul.lproj/Main.xcstrings` | `macOS/Base.lproj/Main.storyboard` | `<objectID>.<property>` |
| `macOS/InfoPlist.xcstrings`, `iOS/InfoPlist.xcstrings` | each app's permission-prompt usage descriptions, bundle name and copyright notice | the property-list key name |
| `macOS/AppShortcuts.xcstrings`, `iOS/AppShortcuts.xcstrings` | the phrases `ServerAppShortcuts` declares | one key per set of phrase variations |

A String Catalog is a per-target resource, which is why each target has its own `Localizable` catalog and each app its own `InfoPlist` and `AppShortcuts` catalog.
The two `InfoPlist` catalogs carry the same reasons, and the two `AppShortcuts` catalogs the same phrases, with the same translations.
All eight must stay complete for every detected language.
They are JSON of one shape: each key maps to a `comment` plus a `localizations` dictionary of `<locale>: {"stringUnit": {"state": ..., "value": ...}}`.
Three variations occur:

- An App Shortcut phrase localizes as a `stringSet`, a list of `values` rather than one `value`, because Xcode collapses every phrase variation into a single key.
- A numeric format, such as an entity type's `numericFormat` (`%lld Nextcloud notes`), localizes as plural `variations`, one `stringUnit` per plural category (`one`, `other`).
- `"shouldTranslate": false` marks an entry Do Not Translate, as a pure format passthrough like `%@` would be, and as `CFBundleName` and `NSHumanReadableCopyright` are.

### The `Localizable` catalogs

The key is the English source string itself, so these catalogs carry no explicit `en` unit, and the check takes the key as the English value.

App Intents strings resolve from the same `Localizable` table, which is why they are in both app catalogs, keyed by the literal source string too.
They are a `LocalizedStringResource` such as an intent's title or description, a `@Parameter` title or `requestValueDialog`, an entity's `DisplayRepresentation` subtitle, and a `TypeDisplayRepresentation`.
`ShortcutsNameTests` checks that the action titles and entity type names are translated in every localization the bundle ships.

A SwiftUI `Text`, `Label`, `Button`, `TextField` or `Link` title is a `LocalizedStringKey`, which SwiftUI localizes on its own, keyed by that literal; the `String(localized:comment:)` rule governs the strings the code passes around itself, not these.
A `Text` can carry its comment through `Text(_:tableName:bundle:comment:)`, and a comment written there is extracted with its key.
`verbatim:` keeps a string out of the extracted keys altogether rather than leaving an entry whose translations all equal the English: `Text(verbatim: "Cirruscope")` for the brand name, and likewise URLs and placeholder examples such as `https://your.nextcloud.com`.

In the widget extension, a `WidgetConfiguration`'s `configurationDisplayName(_:)` and `description(_:)`, the name and blurb the widget gallery shows, are each given a `Text` built from a literal and its `comment:`, so both are extracted with their comments.
The widget rules have two reasons.
A `LocalizedStringKey` is parsed as Markdown along with whatever is interpolated into it, so a server file named `_draft_.md` would render as `draft.md`, silently.
And a word in sentence case uppercased by `.textCase(.uppercase)` at the view gets each language's own uppercasing, applied to its own word rather than to an English one.

No test contributes a key, the test targets setting `SWIFT_EMIT_LOC_STRINGS = NO`, which keeps the check about the app's own strings; see [Testing → Targets and schemes](./Testing.md#targets-and-schemes).

### The storyboard catalog

`macOS/mul.lproj/Main.xcstrings` replaced the per-locale `Main.strings` files the storyboard was once localized through.
A key is `<objectID>.<property>`, such as `5xm-BD-bvl.title`, and its `comment` carries the generated `Class = …; title = …; ObjectID = …;` context, which Xcode always regenerates from the storyboard's current content.
The catalog carries an explicit `en` unit, while the English source wording stays on the storyboard's Base object.

Translating only what the user sees means, here:

- A placeholder replaced at runtime is skipped, such as a label bound to an outlet and assigned in code, like a cell's file-name field.
- An image-only button's title that is never displayed is skipped, unless it also serves as the control's accessibility label.
- The standard AppKit menu titles Xcode emits into the catalog are left untranslated by convention, so only the app's own user-facing strings are translated, not every entry.

### The `InfoPlist` catalogs

The key is the property-list key name, such as `NSCameraUsageDescription`, not the English text, so unlike the `Localizable` catalogs these carry an explicit `en` `stringUnit` as well.
The English of a reason both apps give therefore exists in six places: the `INFOPLIST_KEY_*` build setting in the Debug and the Release configuration of each app target, and the `en` value in each app's catalog.
AGENTS.md → Localization Instructions says which is the source of truth.
[`UsageDescriptionTests`](../Tests/Configuration/UsageDescriptionTests.swift) checks that each reason is present and non-empty in the hosting app's property list, where a misspelled or unsubstituted build setting shows.

`CFBundleName` and `NSHumanReadableCopyright` are Do Not Translate, and their English values come from the xcconfig files rather than the target:

- `CFBundleName` is `PRODUCT_NAME`, which `Cirruscope/Cirruscope.xcconfig` sets to `CIRRUSCOPE_BUNDLE_NAME`, defined in the root `Cirruscope.xcconfig`.
- `NSHumanReadableCopyright` is `INFOPLIST_KEY_NSHumanReadableCopyright` in the root `Cirruscope.xcconfig`, which the iOS target restates in its own build settings.

The prompts name neither the "Nextcloud" trademark nor "Cirruscope", describing the capability generically instead ("during video calls", not "during Nextcloud Talk calls").
That restriction is specific to these prompts: `Localizable.xcstrings` deliberately names both where a message is *about* the server product, as in "Cirruscope requires Nextcloud server version %lld or later."

### The `AppShortcuts` catalogs

They are the `AppShortcuts` table Xcode extracts from the `AppShortcutsProvider`, once for each app target compiling it, like every other String Catalog.
Each key's localizations are a `stringSet` whose `values` hold one entry per source phrase, in the source's order.

## Why `state` is not enough

In all eight catalogs, a `stringUnit`'s or `stringSet`'s `state` is the completeness and staleness signal Xcode itself tracks.
A freshly added or changed source string starts at `"new"` for each locale and reaches `"translated"` only once a value is filled in, and Xcode flags a locale for re-review on its own when the source text changes later.

`state` alone is necessary but not sufficient, which was proven the hard way.
Migrating off the old per-locale `Main.strings` files carried every existing value straight into the catalog and marked it `"translated"` per locale, even for the ~130 entries that were never actually translated and were just sitting there as English text.
So the check also compares each locale's value with the English one, and a match is a real gap unless it is a deliberate exception.

Before that migration, a storyboard menu item's title was renamed without its stale, plain-text translations being updated, and it shipped unnoticed for several changes.
Recognizing that a change touched a user-facing string is what failed there, which is why AGENTS.md asks for the check after any change, not only after one believed to add, rename or remove a string.

### Deliberate values identical to English

A value identical to English is deliberate rather than a gap in four cases:

- the brand name, `Cirruscope`;
- a placeholder example URL, such as `https://your.nextcloud.com` and `https://cloud.example.tld`;
- a storyboard object whose text is fully overwritten at runtime or never shown, such as the `File Name`, `App Name` and `Size or progress description` cells and the `Main Menu` title;
- a genuine cognate, where that language's correct word is spelled the same, such as French `Services`, `Format` and `Ligatures`, German `Text`, and Spanish `General`.

The check reports these on every run, so a run over complete catalogs is not silent; compare its output with a run from before the change.
Every hit on the current catalogs falls into these cases, the other cognates being German `App`, `Downloads`, `Format`, `Name` and `Support`, French `Conversation`, `Note`, `Notifications`, `Page`, `Substitutions`, `Transformations` and `Zoom`, and Spanish `Zoom`.

## The check scripts

Both find the repository root from their own location, so they work from any directory.

### `Tools/check-string-catalogs.py`

It reads `knownRegions` through `plutil` itself and, for every key of the eight catalogs not marked Do Not Translate, in every detected language, prints one line per finding:

- `<catalog>: '<key>' [<locale>] state='new'`, or whichever other state is not `translated`, `state=None` meaning the locale has no entry for that key at all;
- `<catalog>: '<key>' [<locale>] still identical to English: '<value>' (confirm this is a deliberate exception, not a missed translation)`.

How it decides:

- The English value is the explicit `en` `stringUnit`'s value where there is one, and the key otherwise; without that fallback the comparison would be silently skipped in exactly the catalogs most likely to gain new strings.
- A `stringSet` is checked for its `state` alone; its `values` are never compared with English.
- A plural passes when every category is `translated`.
  Otherwise only its first category is examined, so one whose first category is translated and a later one is not passes unreported.

It exits 0 whether or not it reports anything, since only a person can judge an identical-to-English hit, so read its output rather than its exit status.
Only a file it cannot open or parse ends it early, with a Python traceback and a non-zero status.
A clean run rules out only those two failure modes; it cannot tell whether an existing translation reads well.
`--list-locales` prints the detected languages as a Python list, such as `['de', 'fr', 'es']`, and checks nothing.

### `Tools/check-appstore-texts.py`

It walks every `AppStore/<marketing version>/<platform>/` folder, published versions included, and reports:

- a language folder whose files differ from those of `English/`, naming the missing and the extra ones;
- a file that is not one of the fields [AGENTS.md → Repository Structure](../AGENTS.md#repository-structure) lists;
- a file over its field's limit, counted in characters without the trailing newline;
- a file not ending with exactly one newline;
- a file containing an emoji.

It prints every problem at once, to standard error, and exits 1 when there is any; a clean run prints nothing and exits 0.
The emoji test matches character ranges: U+1F000 to U+1FAFF, U+2600 to U+27BF, U+2B00 to U+2BFF, the variation selector U+FE0F and the zero-width joiner U+200D.
A symbol from those blocks, such as ✓ or ★, is therefore reported as well.

## A Shortcuts action in the wrong language

A Shortcuts action showing in the wrong language while the catalogs are complete is the system's action index rather than a catalog gap, as [DECISIONS.md → "Why can the Shortcuts actions appear in English on a Mac set to another language, when every catalog translates them?"](../DECISIONS.md#why-can-the-shortcuts-actions-appear-in-english-on-a-mac-set-to-another-language-when-every-catalog-translates-them) explains.
The two predicates that tell the cases apart, `ToolKitDatabase` for the `locale:` the Shortcuts app queried and `indexLocaleIds` for the languages its index holds, are among the [recipes in Logging.md](./Logging.md#recipes).
`ShortcutsNameTests` covers the half the app answers for.

## App Store texts

The texts in `AppStore/` are localized outside the String Catalogs and outside `knownRegions`.
Their languages are App Store Connect's localizations of the app, English, German, French and Spanish, which match the app's own today but are a list of their own.
Their layout and field limits are in AGENTS.md → Repository Structure, when they change is in AGENTS.md → Documentation Instructions, and why they are in the repository is [DECISIONS.md → "Why are the App Store texts kept in the repository, one folder per version?"](../DECISIONS.md#why-are-the-app-store-texts-kept-in-the-repository-one-folder-per-version).

Background to the rules in AGENTS.md → App Store texts:

- The published 1.1.0 French texts predate the informal-address rule and say "vous"; being published, they stay as they are.
- A quoted UI label is the app's own localized label, word for word, and a system label is the one Apple's localization of macOS shows.
- A macOS feature takes Apple's own term in each language, such as Mitteilungszentrale, centre de notifications and Centro de notificaciones for Notification Center, not the website's, which is wrong in places.
- The Spanish is written for Spain in a way that also reads naturally in Latin America, since those storefronts show the same text.
- A translation runs longer than its English, so an English text close to its field's limit leaves the translations no room.
- App Store Connect rejects a text containing an emoji as having an invalid character, however well it would fit.

The voice and the keyboard-shortcut term the texts share with the app are explained in [DECISIONS.md → "Why does Cirruscope address the user informally in every language?"](../DECISIONS.md#why-does-cirruscope-address-the-user-informally-in-every-language) and [DECISIONS.md → "Why is the settings tab for the server apps' keyboard shortcuts called "Keyboard Shortcuts"?"](../DECISIONS.md#why-is-the-settings-tab-for-the-server-apps-keyboard-shortcuts-called-keyboard-shortcuts).
