<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Logging and Diagnostics

This is how to read what Cirruscope logged, on this Mac, on an iPhone or iPad, or in the Simulator, and why a capture can say less than the code suggests.
How to write a log line is a rule, and stays in [AGENTS.md → Logging and Diagnostics](../AGENTS.md#logging-and-diagnostics) and [AGENTS.md → Adding logging to new code](../AGENTS.md#adding-logging-to-new-code).

## Subsystems

Every behavioural type owns a logger that `Logger(for:)` builds from its own type: the subsystem is the running bundle's identifier and the category is the type name.
That subsystem is `de.i2h3.cirruscope` in both apps and `de.i2h3.cirruscope.widgets` in the widget extension, `Core/` code included when the extension runs it.
That is why the predicates below that read Cirruscope's own logs match the shared prefix with `BEGINSWITH` rather than one subsystem with `==`.
Those are the shipping identifiers: the subsystem follows `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER`, so a run under `de.i2h3.cirruscope.citest` still matches the prefix, while a build under a contributor's own base identifier needs that identifier in every predicate instead.
To narrow a capture to one type, match its name as the `category`, as the third recipe below does.
Several live instances of one type share that category and are told apart by the `(TypeName \(id))` suffix on each message, such as `(WebViewController 3)`, which an `eventMessage CONTAINS` predicate can match.

## Recipes

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

# Which language the Shortcuts app asked its action index for (a Shortcuts action shown in the wrong language):
/usr/bin/log show --last 10m --style compact --predicate 'process == "Shortcuts" AND category == "ToolKitDatabase"'

# Which languages that index holds:
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.apple.shortcuts" AND eventMessage CONTAINS "indexLocaleIds"'
```

The last two read the system's logs rather than Cirruscope's, and tell the system's action index apart from a gap in a String Catalog; what each answer means is in [`DECISIONS.md` → "Why can the Shortcuts actions appear in English on a Mac set to another language, when every catalog translates them?"](../DECISIONS.md#why-can-the-shortcuts-actions-appear-in-english-on-a-mac-set-to-another-language-when-every-catalog-translates-them).

## An iPhone, an iPad or the Simulator

**`log show` reads this Mac's store, not a phone's.**
Nothing the app does on an iPhone reaches this Mac's log, whether it happened in the foreground with Xcode attached or in a background refresh with nobody watching, so the record has to be pulled over first: `sudo /usr/bin/log collect --device-name "<name>" --last 24h --output ~/Desktop/cirruscope.logarchive`, then `log show <archive> --predicate ...` against that.
In the Simulator each device keeps a store of its own, which the host's `log show` does not read either: run the commands above inside it through `xcrun simctl spawn booted`, as in `xcrun simctl spawn booted log show --last 30m --predicate 'subsystem BEGINSWITH "de.i2h3.cirruscope"' --style ndjson`.

## Levels

Only `.notice`, `.error`, and `.fault` are persisted to the store, so those are what `log show --last`/`--start` reliably returns after the fact.
`.debug` and `.info` are ephemeral and appear only while `log stream` (or Instruments) is actively capturing, which is why the rule in [AGENTS.md → Adding logging to new code](../AGENTS.md#adding-logging-to-new-code) puts anything worth retrieving later at `.notice` or higher.
Do not pass `--info` or `--debug` to `log show`: neither level is persisted, so they only imply a completeness the output does not have.
Those levels are captured live, with `log stream --level debug`.

## Why a capture can look emptier than the code suggests

Rule out each of these before concluding a line is missing.

- A `.debug` or `.info` line was never persisted, so no `log show` returns it after the fact, however it is invoked (see "Levels" above).
- Console.app hides `.debug` and `.info` until Action ▸ Include Info/Debug Messages is switched on, which is most of the entry and exit lines.
- Every dynamic value without an explicit `privacy: .public` reads as `<private>` unless the app runs from Xcode or a logging configuration profile that enables private data for the subsystem is installed, so a line that is present can still say nothing.
  The repository does not ship such a profile.

## Signposts

Nothing in the code emits a signpost, and `Core/Logging.swift` has no `OSSignposter(for:)` counterpart to `Logger(for:)`; whether and how to add them is under [AGENTS.md → Logging and Diagnostics](../AGENTS.md#logging-and-diagnostics).
Once there are any, `log show` lists signposts only when it is passed `--signpost`.

## Why the whole of a path is logged

[AGENTS.md → Adding logging to new code](../AGENTS.md#adding-logging-to-new-code) asks for the whole of a path to be logged, not only its ends, and this is what that rule came from.
The fetch layer and the App Intents layer were well covered while the store between them logged nothing at all, and the result was a refresh that could be seen starting and seen donating with no way to tell what it had stored.
