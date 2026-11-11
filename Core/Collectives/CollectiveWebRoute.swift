// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectiveWebRoute` is where a collective lives in the web interface.
enum CollectiveWebRoute {
    /// `appID` is the identifier of the Nextcloud app that owns a collective and the pages within it, which is what its icon is cached under.
    static let appID = "collectives"

    /// `url(for:on:)` is the address of `collective` on `serverAddress`, or `nil` when there is nothing to address it by.
    static func url(for collective: CollectiveTransferObject, on serverAddress: URL) -> SameOriginURL? {
        guard let components = components(for: collective) else {
            return nil
        }

        return SameOriginURL(components: components, relativeTo: serverAddress)
    }

    /// `components(for:)` are the path segments addressing a collective, or `nil` when there is nothing to address it by.
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
