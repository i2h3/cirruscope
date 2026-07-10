<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Cirruscope

[![REUSE](https://api.reuse.software/badge/github.com/i2h3/cirruscope)](https://api.reuse.software/info/github.com/i2h3/cirruscope)

An app-like Nextcloud experience on macOS.
This elevates your Nextcloud user interface to the next level by leveraging native platform features and WebKit.

This document is written for developers.
For a more user-friendly introduction, see [the official website](https://cirruscope.app).

## Project Status

This is still under development but closing in fast on the initial release of version 1.0.0.

## Features

- Full size content view, no macOS window titlebar or toolbar.
- Windows can be dragged by the Nextcloud top bar.
- Edge to edge content, no unnecessary gaps.
- Sidebar visibility control through app menu item.
- Nextcloud server app speed dials in app menu and dock menu with configurable keyboard shortcuts.
- Window state restoration on relaunch.
- File downloads into the Downloads folder, with a progress window and completion notifications.

## Logging

Cirruscope logs through Apple's unified logging system (`os.Logger`). Every type logs under the subsystem `de.i2h3.cirruscope` with its own type name as the category, and the asynchronous facilities (asset caching, server validation, sign-in, downloads, launch, and page loads) additionally emit `OSSignposter` intervals.

Capture a live, machine-readable stream while the app runs:

```bash
log stream --debug --predicate 'process == "Cirruscope"' --level debug --style ndjson
```

Filter to a single category (type) — for example the download coordinator:

```bash
log stream --predicate 'subsystem == "de.i2h3.cirruscope" && category == "DownloadManager"' --level debug
```

To view the signpost intervals as a timeline, record the app in **Instruments** with the *os_signpost* (or *Points of Interest*) instrument.

### Revealing redacted values

Dynamic values such as URLs, file names, and error messages are logged **privately** and appear as `<private>` in captures, which protects user data by default. They are shown automatically when the app runs from Xcode. To reveal them in a `log` capture on a development machine, install a logging **configuration profile** that enables private data for the subsystem.

Save the following as `Cirruscope-Logging.mobileconfig`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.system.logging</string>
            <key>PayloadIdentifier</key>
            <string>de.i2h3.cirruscope.logging</string>
            <key>PayloadUUID</key>
            <string>4F3F20ED-E83B-491A-BB4C-3C6ED60C0F3B</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadDisplayName</key>
            <string>Cirruscope Logging</string>
            <key>Subsystems</key>
            <dict>
                <key>de.i2h3.cirruscope</key>
                <dict>
                    <key>Enable-Private-Data</key>
                    <true/>
                </dict>
            </dict>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Cirruscope Logging</string>
    <key>PayloadIdentifier</key>
    <string>de.i2h3.cirruscope.logging.profile</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>E8D6331A-C9D3-4324-A263-067ABA5DA123</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadScope</key>
    <string>System</string>
</dict>
</plist>
```

Double-click the file, then approve it under **System Settings ▸ General ▸ Device Management**. With the profile installed, the same `log stream` command shows the previously `<private>` values in the clear. **Remove the profile when you are done** (same pane ▸ select *Cirruscope Logging* ▸ Remove) so private data is no longer written to the log unprotected.

## Disclaimer

This is an unofficial third-party app out of the Nextcloud community.
It is not associated with or endorsed by Nextcloud GmbH.

## License

See [LICENSE](./LICENSE).
