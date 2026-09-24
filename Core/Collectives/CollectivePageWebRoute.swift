// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectivePageWebRoute` is where one page within a collective lives in the web interface.
///
/// **This is the only route in the app that has not been checked against a live server, and it is the one most likely to be wrong.** Talk's conversation route was read out of the app's own controller and the Notes route out of its `routes.php`; the Collectives app is installed on none of the instances available here, so this is derived from a production URL captured from an instance in the wild plus what the network library documents about the fields. What that URL showed is a path carrying the page's whole ancestor chain and a `fileId` query item: `/apps/collectives/<collective>/<ancestor titles…>/<page>?fileId=<id>`.
///
/// So the shape is built to fail *visibly* rather than plausibly. The `fileId` is carried because it is the part the server can resolve a page from even if the path segments do not match what it expects, which makes the likely failure "the page loads anyway" or "the collective loads" rather than "a different page loads". A page whose address cannot be built at all answers `nil`, and the caller opens the collective instead — the closest thing that is certainly right.
///
/// What to check against an instance with Collectives installed, in order of how much it would change here: whether the collective segment is the slug, the name, or the slug with the identifier appended; whether the page part is the full ancestor chain or a single slug-and-identifier segment; and whether a correct `fileId` with a wrong path still opens the right page. If the last is true, everything before it stops mattering.
enum CollectivePageWebRoute {
    /// `pathComponents(forFileName:filePath:)` are the segments addressing a page inside its collective.
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

    /// `url(collectiveSlug:collectiveName:page:on:)` is the address of `page` within its collective on `serverAddress`, or `nil` when it cannot be built.
    ///
    /// The page at the root of a collective is addressed by the collective itself, which is not a fallback but the correct answer: it is the page shown when the collective is opened, and there is no separate address for it.
    static func url(collectiveSlug: String?, collectiveName: String, page: CollectivePageTransferObject, on serverAddress: URL) -> SameOriginURL? {
        guard let collective = CollectiveWebRoute.url(forSlug: collectiveSlug, name: collectiveName, on: serverAddress) else {
            return nil
        }

        guard page.isLandingPage == false else {
            return collective
        }

        let components = pathComponents(forFileName: page.fileName, filePath: page.filePath)

        guard components.isEmpty == false else {
            return collective
        }

        var address = collective.url

        for component in components {
            address = address.appending(path: component)
        }

        address = address.appending(queryItems: [URLQueryItem(name: "fileId", value: String(page.id))])

        return SameOriginURL(path: address.absoluteString, relativeTo: serverAddress)
    }
}
