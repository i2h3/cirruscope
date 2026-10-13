# SPDX-FileCopyrightText: 2026 Iva Horn
# SPDX-License-Identifier: MIT

"""
Checks every String Catalog for a translation that is missing, and for one still identical to English.

Every key of each catalog not marked Do Not Translate is checked in every localization the Xcode project's `knownRegions` enables, `en` and `Base` excepted.
A translation whose `state` is not `translated` is reported with that state, and a translated one still identical to the English source is reported for a person to confirm as a deliberate exception.
The script exits 0 either way, since only a person can judge an identical-to-English hit.
With `--list-locales` it prints the detected localizations instead and checks nothing.
Run it as `python3 Tools/check-string-catalogs.py` from anywhere in the repository; see AGENTS.md → Localization Instructions.
"""

import argparse
import json
import os
import pathlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--list-locales", action="store_true", help="print the localizations knownRegions enables, en and Base excepted, and check nothing")
arguments = parser.parse_args()

# Every path below is relative to the repository root, whichever directory the script is run from.
os.chdir(pathlib.Path(__file__).resolve().parent.parent)

pbxproj = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", "Cirruscope.xcodeproj/project.pbxproj"]))
known_regions = next(o["knownRegions"] for o in pbxproj["objects"].values() if o.get("isa") == "PBXProject")
locales = [r for r in known_regions if r not in ("en", "Base")]

if arguments.list_locales:
    print(locales)
    raise SystemExit

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
