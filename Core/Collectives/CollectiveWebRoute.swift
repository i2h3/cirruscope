// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectiveWebRoute` is where a collective lives in the web interface.
///
/// A collective sits under its app's own prefix, `/apps/collectives/<segment>`, so the path names its owner and `ServerAppTransferObject`'s resolution rule recognizes it without `ServerAppPath` needing an entry for it. It is appended to the server address rather than written from the root, for the reason every route the app builds itself is: an address the *server* named already carries the instance's web root, and one the app builds does not.
///
/// The segment is the collective's `slug` where it has one and its `name` otherwise. That is what the network library's own documentation says the field is for — "the url-safe form of `name` the server uses when addressing the collective in a link" — and the fallback exists because it also says the field is absent on a server whose Collectives app predates slugs, so a client building links has to be prepared for it.
enum CollectiveWebRoute {
    /// `appID` is the identifier of the Nextcloud app that owns a collective and the pages within it, which is what its icon is cached under.
    ///
    /// Not a second fact but the same one written where it can be used: Nextcloud serves an app under `/apps/<app id>/`, so the `/apps/collectives/…` route this builds names it outright. It is stated here rather than at each surface that needs it, because a surface guessing at it would be guessing at something this file already knows.
    static let appID = "collectives"

    /// `url(forSlug:name:on:)` is the address of a collective on `serverAddress`, or `nil` when there is nothing to address it by.
    ///
    /// It answers `nil` exactly when `components(forSlug:name:)` does, which is where the reason for refusing lives.
    static func url(forSlug slug: String?, name: String, on serverAddress: URL) -> SameOriginURL? {
        guard let components = components(forSlug: slug, name: name) else {
            return nil
        }

        return SameOriginURL(components: components, relativeTo: serverAddress)
    }

    /// `components(forSlug:name:)` are the path segments addressing a collective, or `nil` when there is nothing to address it by.
    ///
    /// Shared with the route that addresses a page, because a page's address begins with its collective's: stating the segments once is what keeps the two from disagreeing about which of the slug and the name is used.
    /// Both an absent slug and an empty name are refused rather than guessed at, because the guess would not fail visibly: `/apps/collectives/` with nothing after it is the collectives overview, a real page that loads, so a user asking for one collective would be shown the list of all of them with nothing to say the app had not understood.
    static func components(forSlug slug: String?, name: String) -> [String]? {
        let segment = slug?.isEmpty == false ? slug! : name

        guard segment.isEmpty == false else {
            return nil
        }

        return ["apps", "collectives", segment]
    }
}
