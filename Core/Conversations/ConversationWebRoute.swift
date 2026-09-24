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
/// It is built through `SameOriginURL(components:relativeTo:)`, which appends to the server address rather than resolving from the server root, and that is the whole of what makes a subdirectory install work. `SameOriginURL` documents the distinction; the short of it is that every address the *server* names already carries the instance's web root and one the app knows does not. The test covering a subdirectory install is there because that failure looked like a working link.
enum ConversationWebRoute {
    /// `url(forToken:on:)` is the address of the conversation `token` names on `serverAddress`, or `nil` when there is no address to be confident in.
    ///
    /// Both ways of answering `nil` are the initializer's rather than this type's, and both matter here. An empty token is refused there as an empty component, which is what this needs: appending nothing would produce the address of Talk's own conversation list — a real page that opens and looks like an answer to a question nobody asked. An address that does not resolve on the server means the server address itself is unusable, which is `SameOriginURL`'s judgement to make and not this type's to second-guess.
    static func url(forToken token: String, on serverAddress: URL) -> SameOriginURL? {
        SameOriginURL(components: ["call", token], relativeTo: serverAddress)
    }
}
