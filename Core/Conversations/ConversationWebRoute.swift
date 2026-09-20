// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ConversationWebRoute` is where a Nextcloud Talk conversation lives in the web interface.
///
/// Talk registers this route at the server's own root rather than under its app prefix, by declaring `root: ''` on the controller, so a conversation is at `/call/<token>` and not at `/apps/spreed/…`. That is the same fact `ServerAppPath.appPathsByRootRoute` already records from the other direction — it is what lets a loaded `/call/…` page be recognized as Talk's — and it is the reason this cannot be derived from the app's own `href` the way an ordinary app's page could.
///
/// The token is what addresses a conversation, never the numeric identifier the server also reports: the route's own requirement is four to thirty lowercase alphanumeric characters, which a number could satisfy only by accident.
/// The result is resolved through `SameOriginURL`, so a path this builds is proven to stay on the server that named the conversation before anything attaches the account's app password to it.
///
/// It is appended to the server address rather than written as a path from the root, and the difference is the whole of what makes a subdirectory install work. Every other address in this app comes from the server — a navigation entry's `href`, a theming background — and the server writes its own web root into each of them, so resolving those from the root is correct. This route is one the *app* knows, so nothing has put the web root in front of it: read as a root-relative path against an instance served from `/nextcloud`, `/call/<token>` resolves to `https://example.com/call/<token>` and opens a page on that host which has nothing to do with the account. Appending keeps the web root, and the test covering a subdirectory install is there because that failure looked like a working link.
enum ConversationWebRoute {
    /// `url(forToken:on:)` is the address of the conversation `token` names on `serverAddress`, or `nil` when there is no address to be confident in.
    ///
    /// It answers `nil` rather than guessing, and both refusals are real. An empty token would produce the address of Talk's own conversation list, which is a different page from the one that was asked for and would look like the app had opened the wrong thing rather than nothing. An address that does not resolve on the server means the server address itself is unusable, which is `SameOriginURL`'s judgement to make and not this type's to second-guess.
    static func url(forToken token: String, on serverAddress: URL) -> SameOriginURL? {
        guard token.isEmpty == false else {
            return nil
        }

        let address = serverAddress.appending(path: "call").appending(path: token)

        return SameOriginURL(path: address.absoluteString, relativeTo: serverAddress)
    }
}
