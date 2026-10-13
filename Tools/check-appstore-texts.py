# SPDX-FileCopyrightText: 2026 Iva Horn
# SPDX-License-Identifier: MIT

"""
Checks every App Store text against its field's limit, and every language against English.

Each language folder of a version must hold the same files as its `English/` folder, each file must name a field this project records and stay within that field's limit, end with exactly one newline and contain no emoji.
The script prints every problem it finds and exits non-zero when there is one.
Run it as `python3 Tools/check-appstore-texts.py` from anywhere in the repository; see AGENTS.md → Localization Instructions → App Store texts.
"""

import os
import pathlib
import re
import sys

# Every path below is relative to the repository root, whichever directory the script is run from.
os.chdir(pathlib.Path(__file__).resolve().parent.parent)

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
