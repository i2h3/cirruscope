// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

/// `SafariUserAgentProbe` reports what a real `WebPage` tells a page it is, given an application name.
@MainActor
enum SafariUserAgentProbe {
    /// What `navigator.userAgent` reports in a `WebPage` configured with `applicationName`, or `nil` if the page returns something other than a string.
    static func reportedUserAgent(applicationName: String?) async throws -> String? {
        var configuration = WebPage.Configuration()
        configuration.applicationNameForUserAgent = applicationName

        let page = WebPage(configuration: configuration)

        for try await event in page.load(URL(string: "about:blank")!) where event == .finished {
            break
        }

        return try await page.callJavaScript("return navigator.userAgent;") as? String
    }
}
