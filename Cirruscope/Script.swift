// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `Script` enumerates the JavaScript both apps inject into their web view, and loads it from the bundle on demand.
enum Script: String {
    /// `sidebarToggle` clicks Nextcloud's app-navigation toggle to show or hide the navigation.
    case sidebarToggle = "SidebarToggle"

    /// `sidebarToggleState` observes Nextcloud's app-navigation toggle and reports its availability and expanded state through the `sidebarToggleState` message handler.
    case sidebarToggleState = "SidebarToggleState"

    /// `pageLanguage` contributes `pageLanguage` to the page's `Cirruscope` namespace, answering the language the server rendered the document in for a signed-in user, or `null`.
    case pageLanguage = "PageLanguage"

    /// `localStorageRetention` makes clearing a storage area do nothing in the server's page, so the preferences Nextcloud keeps in local storage survive a lapsed browser session.
    ///
    /// Nextcloud clears the page's storage before sending a lapsed session to its sign-in form, which both apps cancel and answer by signing the same account straight back in, so nothing would be left of that episode but lost preferences.
    /// Both apps install it as a user script that runs at the start of every document load, in the main frame alone, so no embedded frame from another origin is changed by it.
    case localStorageRetention = "LocalStorageRetention"

    /// `styleSheet` appends the app's bundled `Cirruscope.css` to the document as a `<style>` element.
    case styleSheet = "Cirruscope"

    /// Records failures to load a bundled resource under the `Script` category.
    private static let logger = Logger(for: Script.self)

    /// The file extension of the resource behind this case.
    private var resourceExtension: String {
        switch self {
            case .sidebarToggle, .sidebarToggleState, .pageLanguage, .localStorageRetention:
                "js"

            case .styleSheet:
                "css"
        }
    }

    /// The JavaScript to inject or evaluate for this case, or `nil` if the resource behind it is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use, so edits to the underlying file take effect without any change to Swift source.
    var source: String? {
        guard let contents = resourceContents else {
            return nil
        }

        switch self {
            case .sidebarToggle, .sidebarToggleState, .pageLanguage, .localStorageRetention:
                return contents

            case .styleSheet:
                return Self.injection(of: contents)
        }
    }

    /// The text of the bundled resource behind this case, or `nil` when it cannot be read.
    private var resourceContents: String? {
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: resourceExtension), let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            Self.logger.error("Could not load bundled resource \(self.rawValue).\(self.resourceExtension)")
            return nil
        }

        return contents
    }

    /// Wraps `styleSheet` in the script that appends it to the document as a `<style>` element.
    private static func injection(of styleSheet: String) -> String {
        let escaped = styleSheet
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")

        return """
        (function() {
            var style = document.createElement('style');
            style.textContent = `\(escaped)`;
            document.documentElement.appendChild(style);
        })();
        """
    }
}
