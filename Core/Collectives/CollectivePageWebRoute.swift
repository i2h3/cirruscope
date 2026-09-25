// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectivePageWebRoute` is where one page within a collective lives in the web interface.
///
/// This was for a long time the one address in the app not read out of the owning app's own routing, because the Collectives app declares only a catch-all on the server and decides the rest in its Vue router. It is now read out of that router — `src/router.js` in `nextcloud/collectives` — so the caveat is retired. Every collective route there carries the same two children, in this order:
///
///     { path: ':pageSlug-:pageId(\\d+)', component: CollectiveView },
///     { path: ':page(.*)', component: CollectiveView },
///
/// So a page is addressed by `<slug>-<id>` where it has a slug, and by a path otherwise. The first is what this builds wherever it can: it is unambiguous, both halves come from the server, and it is the form the app's own links carry. The second is the fallback for a server whose Collectives app predates slugs, and is the whole ancestor chain — which is what the earlier, derived version of this route built for every page, and why pages that resolved perfectly well still opened the wrong thing on an instance that had slugs.
enum CollectivePageWebRoute {
    /// `pathComponents(forFileName:filePath:)` are the segments addressing a page by its place in the collective, for a server that gave it no slug.
    ///
    /// The folder comes first and the file second, with one exception. A page that has subpages is stored as the index file of a folder named after itself, and that file is always called `Readme.md`, so appending its name would repeat the page's own title in the path. The file name is therefore dropped for exactly that case, rather than for every page whose path is non-empty.
    static func pathComponents(forFileName fileName: String, filePath: String) -> [String] {
        var components = filePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        guard fileName != "Readme.md" else {
            return components
        }

        let title = fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName

        guard title.isEmpty == false else {
            return components
        }

        components.append(title)
        return components
    }

    /// `url(for:in:on:)` is the address of `page` within `collective` on `serverAddress`, or `nil` when it cannot be built.
    ///
    /// The page at the root of a collective is addressed by the collective itself, which is not a fallback but the correct answer: it is the page shown when the collective is opened, and there is no separate address for it.
    static func url(for page: CollectivePageTransferObject, in collective: CollectiveTransferObject, on serverAddress: URL) -> SameOriginURL? {
        guard let collectiveComponents = CollectiveWebRoute.components(for: collective) else {
            return nil
        }

        guard page.isLandingPage == false else {
            return SameOriginURL(components: collectiveComponents, relativeTo: serverAddress)
        }

        if let slug = page.slug, slug.isEmpty == false {
            return SameOriginURL(components: collectiveComponents + ["\(slug)-\(page.id)"], relativeTo: serverAddress)
        }

        let pageComponents = pathComponents(forFileName: page.fileName, filePath: page.filePath)

        guard pageComponents.isEmpty == false else {
            return SameOriginURL(components: collectiveComponents, relativeTo: serverAddress)
        }

        guard let pageAddress = SameOriginURL(components: collectiveComponents + pageComponents, relativeTo: serverAddress) else {
            return nil
        }

        // Only on this branch, and only because it is the uncertain one: a path built from titles can be wrong
        // where a slug and an identifier cannot, and the file identifier is the part the server can resolve a
        // page from even when the path does not match what it expects. The query item is added after the origin
        // has been proven rather than before, because it is not part of the path and cannot move the address to
        // another server: appending it to an address already known to be the account's leaves it the account's.
        let address = pageAddress.url.appending(queryItems: [URLQueryItem(name: "fileId", value: String(page.id))])

        return SameOriginURL(path: address.absoluteString, relativeTo: serverAddress)
    }
}
