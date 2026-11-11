// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `PageLanguage` is the language the connected server last rendered a signed-in page in, and the decision whether a page arriving in another one means the account's language has changed.
struct PageLanguage {
    /// `current` is the language the last signed-in page was rendered in, or `nil` before one has finished loading.
    private(set) var current: String?

    /// `query` is the function body both web views call once a page has finished loading, answering the page's language or `null`, or `nil` itself when the bundled script is missing.
    static var query: String? {
        guard let source = Script.pageLanguage.source else {
            return nil
        }

        return "\(source)\nreturn window.Cirruscope.pageLanguage();"
    }

    /// `adopt(_:)` records `reported` as the current language and answers whether it differs from one recorded before it; `nil` and an empty string record nothing.
    mutating func adopt(_ reported: String?) -> Bool {
        guard let reported, reported.isEmpty == false else {
            return false
        }

        let previous = current
        current = reported

        guard let previous else {
            return false
        }

        return previous != reported
    }
}
