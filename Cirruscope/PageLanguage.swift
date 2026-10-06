// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `PageLanguage` is the language the connected server last rendered a signed-in page in, and the decision whether a page arriving in another one means the account's language has changed.
///
/// Nextcloud names the apps in its navigation in the account's language, and a language changed in its personal settings does nothing but reload the page, so without this the app list both apps persist kept the previous language's names until the next launch (issue #138).
/// The server writes `<html lang>` from the same lookup that translates those names, which is what makes a change of that attribute the moment to fetch the list again.
/// The first language seen is a baseline rather than a change, on the assumption that the session which loaded the first page fetched the list as it started; a Mac that could not reach the server at launch fetches none until a later window or launch, as before, and only a change seen after that baseline is caught.
/// A report that is stale or belongs to another account costs redundant fetches, whose writes are admitted like any refresh's and whose names are the server's own, so it can never record a wrong one: the first page after a sign-out costs one, and a page restored from the back-forward cache two, one as it arrives and one as the next fresh page does.
/// It is here rather than in `Core/` because it is a decision both web views share, and the widget extension has no web view.
struct PageLanguage {
    /// `current` is the language the last signed-in page was rendered in, or `nil` before one has finished loading.
    private(set) var current: String?

    /// `query` is the function body both web views call once a page has finished loading, answering the page's language or `null`, or `nil` itself when the bundled script is missing.
    ///
    /// It is a function body rather than an expression because that is what `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` and `WebPage.callJavaScript(_:arguments:in:contentWorld:)` both take.
    /// One spelling therefore serves both apps.
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
