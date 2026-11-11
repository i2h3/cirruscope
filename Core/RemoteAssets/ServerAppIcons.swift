// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import os
import Rainmaker
import Synchronization

/// `ServerAppIcons` keeps the icon of every Nextcloud app the server offers, and hands one over as a bitmap whenever a menu is being built.
final class ServerAppIcons: Sendable {
    /// `shared` is the process-wide store of server app icons.
    static let shared = ServerAppIcons()

    /// `cache` is where the icons themselves live on disk.
    private let cache: AssetCache

    /// `rendered` holds the bitmaps already produced, keyed by the app, size, and scale they were produced for.
    private let rendered = Mutex<[String: CGImage]>([:])

    /// `logger` records icon fetching and rendering under the `ServerAppIcons` category.
    private let logger = Logger(for: ServerAppIcons.self)

    /// `init(cache:)` creates a store over `cache`, which defaults to the process-wide one.
    init(cache: AssetCache = .shared) {
        self.cache = cache
    }

    /// `image(forAppID:serverAddress:size:scale:)` is the icon of one app as a bitmap, or `nil` if none has been downloaded or it cannot be drawn.
    func image(forAppID appID: String, serverAddress: URL, size: CGSize, scale: CGFloat) -> CGImage? {
        let key = Self.renderKey(appID: appID, serverAddress: serverAddress, size: size, scale: scale)

        if let existing = rendered.withLock({ $0[key] }) {
            return existing
        }

        guard let data = cache.data(forKey: Self.cacheKey(appID: appID, serverAddress: serverAddress)) else {
            return nil
        }

        guard let glyph = SVGGlyph(data: data) else {
            logger.notice("The icon cached for '\(appID, privacy: .public)' is not an SVG this can draw")
            return nil
        }

        guard let image = SVGGlyphRasterizer.image(of: glyph, size: size, scale: scale) else {
            return nil
        }

        rendered.withLock { $0[key] = image }

        return image
    }

    /// `glyph(forAppID:serverAddress:)` is the icon of one app as vector shapes, or `nil` if none has been downloaded or it cannot be read.
    func glyph(forAppID appID: String, serverAddress: URL) -> SVGGlyph? {
        guard let data = cache.data(forKey: Self.cacheKey(appID: appID, serverAddress: serverAddress)) else {
            return nil
        }

        guard let glyph = SVGGlyph(data: data) else {
            logger.notice("The icon cached for '\(appID, privacy: .public)' is not an SVG this can draw")
            return nil
        }

        return glyph
    }

    /// `refresh(_:serverAddress:credentials:)` downloads the icon of every app in `items`, and reports whether any of them changed what a menu would draw.
    @discardableResult
    func refresh(_ items: [NavigationItem], serverAddress: URL, credentials: Credentials?) async -> Bool {
        await withTaskGroup(of: String?.self) { group in
            for item in items {
                guard let asset = SameOriginURL(path: item.icon, relativeTo: serverAddress) else {
                    logger.notice("The icon path offered for '\(item.id, privacy: .public)' does not stay on the server; ignoring it")
                    continue
                }

                group.addTask { [cache, logger] in
                    do {
                        try await cache.cache(remote: asset, key: Self.cacheKey(appID: item.id, serverAddress: serverAddress), authenticatedAs: credentials)
                        return item.id
                    } catch {
                        logger.notice("Could not fetch the icon for '\(item.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }

            var didFetchAny = false

            for await appID in group {
                guard let appID else {
                    continue
                }

                didFetchAny = true

                // The bytes on disk may be new ones, so anything already drawn from the old ones is stale.
                rendered.withLock { store in
                    let stale = store.keys.filter { $0.hasPrefix("\(appID)\u{1}") }

                    for key in stale {
                        store.removeValue(forKey: key)
                    }
                }
            }

            return didFetchAny
        }
    }

    /// `clear()` forgets every bitmap drawn so far.
    func clear() {
        rendered.withLock { $0.removeAll() }
    }

    /// `cacheKey(appID:serverAddress:)` is where an app's icon is stored on disk, named after the two things a menu knows without having asked the server anything.
    private static func cacheKey(appID: String, serverAddress: URL) -> String {
        "server-app-icon\u{1}\(serverAddress.absoluteString)\u{1}\(appID)"
    }

    /// `renderKey(appID:serverAddress:size:scale:)` identifies one drawn bitmap, since the same icon is wanted at more than one size.
    private static func renderKey(appID: String, serverAddress: URL, size: CGSize, scale: CGFloat) -> String {
        "\(appID)\u{1}\(serverAddress.absoluteString)\u{1}\(size.width)x\(size.height)@\(scale)"
    }
}
