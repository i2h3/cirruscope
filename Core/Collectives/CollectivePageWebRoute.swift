// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectivePageWebRoute` is where one page within a collective lives in the web interface.
///
///     { path: ':pageSlug-:pageId(\\d+)', component: CollectiveView },
///     { path: ':page(.*)', component: CollectiveView },
enum CollectivePageWebRoute {
    /// `pathComponents(forFileName:filePath:)` are the segments addressing a page by its place in the collective, for a server that gave it no slug.
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
