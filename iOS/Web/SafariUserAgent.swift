// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SafariUserAgent` builds the application name `NextcloudView` appends to its web view's user agent so Nextcloud reads the page as being shown in Safari.
enum SafariUserAgent {
    /// The tokens that follow WebKit's own, completing the user agent into one Safari sends.
    static var applicationName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        return "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1"
    }
}
