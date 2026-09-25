// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectiveWebRoute` is where a collective lives in the web interface.
///
/// Unlike Talk's and Notes' routes, which the server declares in a `routes.php` this project read, the Collectives app declares only a catch-all on the server (`/{path}` → `start#indexPath`) and decides everything in its own Vue router. So this is read out of that router — `src/router.js` in `nextcloud/collectives` — which is the same standard, applied to the place the app actually keeps its routing.
///
/// What that router declares, in order, is two ways to address a collective: `'/:collectiveSlug-:collectiveId(\\d+)'` first and `'/:collective'` after it. This builds the first where it can and the second otherwise, which is the fallback the library's own documentation asks for — a slug is `nil` on a server whose Collectives app predates slugs.
enum CollectiveWebRoute {
    /// `appID` is the identifier of the Nextcloud app that owns a collective and the pages within it, which is what its icon is cached under.
    ///
    /// Not a second fact but the same one written where it can be used: Nextcloud serves an app under `/apps/<app id>/`, so the `/apps/collectives/…` route this builds names it outright. It is stated here rather than at each surface that needs it, because a surface guessing at it would be guessing at something this file already knows.
    static let appID = "collectives"

    /// `url(for:on:)` is the address of `collective` on `serverAddress`, or `nil` when there is nothing to address it by.
    ///
    /// It answers `nil` exactly when `components(for:)` does, which is where the reason for refusing lives.
    static func url(for collective: CollectiveTransferObject, on serverAddress: URL) -> SameOriginURL? {
        guard let components = components(for: collective) else {
            return nil
        }

        return SameOriginURL(components: components, relativeTo: serverAddress)
    }

    /// `components(for:)` are the path segments addressing a collective, or `nil` when there is nothing to address it by.
    ///
    /// Shared with the route that addresses a page, because a page's address begins with its collective's: stating the segments once is what keeps the two from disagreeing about which form is used.
    /// The segment is `<slug>-<id>` where there is a slug, which is the form the app's own router matches first and the form its own links carry. Where there is none the name stands alone, matching the router's second pattern — that is a real server's answer rather than a guess, the library documenting `slug` as `nil` on an instance whose Collectives app predates slugs.
    /// An empty name with no slug is refused rather than guessed at, because the guess would not fail visibly: `/apps/collectives/` with nothing after it is the collectives overview, a real page that loads, so a user asking for one collective would be shown the list of all of them with nothing to say the app had not understood.
    static func components(for collective: CollectiveTransferObject) -> [String]? {
        guard let segment = segment(for: collective) else {
            return nil
        }

        return ["apps", appID, segment]
    }

    /// `segment(for:)` is the one path segment naming a collective, or `nil` when it cannot be named.
    static func segment(for collective: CollectiveTransferObject) -> String? {
        if let slug = collective.slug, slug.isEmpty == false {
            return "\(slug)-\(collective.id)"
        }

        guard collective.name.isEmpty == false else {
            return nil
        }

        return collective.name
    }
}
