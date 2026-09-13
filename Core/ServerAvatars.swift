// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import os
import Rainmaker
import Synchronization

/// `ServerAvatars` keeps the profile photograph of every Nextcloud user the app has drawn a circle for, and hands one over as a bitmap whenever a row is being built.
///
/// It is the sibling of `ServerAppIcons` and works the same way: cached on disk under a key built from the user and the server rather than from the path they were fetched from, read synchronously because a view is drawn the moment it is asked for, and answering `nil` as an ordinary result rather than a failure.
/// What differs is what gets cached at all. Nextcloud answers the avatar endpoint for every user it knows, drawing a monogram itself when that user uploaded nothing, so a fetch always succeeds and the bytes alone never reveal which was received. Only `UserAvatar.isCustom` does. This stores a photograph and deliberately stores nothing for a generated one, which makes a cache miss mean exactly one thing to a caller — draw your own monogram — and keeps the app's circle style from being replaced by the server's wherever somebody has no picture.
/// `ImageIO` rather than `NSImage` or `UIImage`, because this is compiled into the widget extension as well and `Core/` may depend on neither AppKit nor UIKit.
final class ServerAvatars: Sendable {
    /// `shared` is the process-wide store of user avatars.
    static let shared = ServerAvatars()

    /// `cache` is where the photographs themselves live on disk.
    private let cache: AssetCache

    /// `decoded` holds the bitmaps already produced, keyed by the user and server they were produced for.
    ///
    /// A `Mutex` rather than an actor for the same reason `ServerAppIcons` uses one: the readers are views being laid out, which cannot `await`.
    private let decoded = Mutex<[String: CGImage]>([:])

    /// `withoutPhotograph` remembers which users the server answered for with a generated monogram, so the same answer is not fetched again for the life of the process.
    ///
    /// Without it every refresh would re-request an avatar for every user who has none, which on a feed of colleagues is most of them. It is deliberately not persisted: somebody uploading a picture should see it appear, and a process that ends is the bound on how long this can be wrong.
    private let withoutPhotograph = Mutex<Set<String>>([])

    /// `logger` records avatar fetching and decoding under the `ServerAvatars` category.
    private let logger = Logger(for: ServerAvatars.self)

    /// `init(cache:)` creates a store over `cache`, which defaults to the process-wide one.
    init(cache: AssetCache = .shared) {
        self.cache = cache
    }

    /// `image(forUserID:serverAddress:)` is the photograph of one user as a bitmap, or `nil` when they have none or it cannot be decoded.
    ///
    /// A `nil` is the ordinary answer, not a failure: nothing has been fetched on a first launch, and a user who uploaded no picture never gets one cached at all. Either way the caller draws its own monogram.
    func image(forUserID userID: String, serverAddress: URL) -> CGImage? {
        let key = Self.cacheKey(userID: userID, serverAddress: serverAddress)

        if let existing = decoded.withLock({ $0[key] }) {
            return existing
        }

        guard let data = cache.data(forKey: key) else {
            return nil
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger.notice("The avatar cached for a user is not an image this can decode")
            return nil
        }

        decoded.withLock { $0[key] = image }

        return image
    }

    /// `refresh(userIDs:on:)` fetches the avatar of each named user that has not already been answered for, storing the photographs and remembering who has none.
    ///
    /// `server` is a `Rainmaker.Server` the caller has already built and authenticated, because this is called from a place that has just used one — a widget's timeline provider, having fetched the activity the users were named by.
    /// Fetches run one after another rather than concurrently. A widget refresh is not a place to open a dozen sockets at once, and the count here is bounded by the rows a layout draws.
    /// Nothing is thrown. An avatar that cannot be fetched leaves the cache as it was, and the caller draws a monogram for it, which is the same outcome as a user who has no photograph.
    func refresh(userIDs: some Sequence<String>, on server: Server) async {
        let serverAddress = server.address

        for userID in Set(userIDs) {
            let key = Self.cacheKey(userID: userID, serverAddress: serverAddress)

            if withoutPhotograph.withLock({ $0.contains(key) }) {
                continue
            }

            do {
                let avatar = try await server.userAvatar(userID, size: .small, darkTheme: false)

                guard avatar.isCustom else {
                    // The server drew this one itself. Remembering that is what stops it being asked again, and discarding any
                    // photograph already cached is what makes a picture disappear from the app when its owner removes it.
                    withoutPhotograph.withLock { _ = $0.insert(key) }
                    cache.remove(forKey: key)
                    decoded.withLock { $0[key] = nil }
                    continue
                }

                cache.store(avatar.data, forKey: key)
                decoded.withLock { $0[key] = nil }

                logger.debug("Cached the avatar of a user as \(avatar.contentType, privacy: .public)")
            } catch {
                logger.notice("Could not fetch the avatar of a user: \(error.localizedDescription)")
            }
        }
    }

    /// `clear()` drops every decoded bitmap and every remembered absence, for a sign-out.
    ///
    /// The cached files themselves are removed by `AssetCache.clear()`, which runs beside this when an account is disconnected; this is what stops the ones already decoded from outliving them in memory, exactly as `ServerAppIcons.clear()` does.
    func clear() {
        decoded.withLock { $0.removeAll() }
        withoutPhotograph.withLock { $0.removeAll() }
    }

    /// `cacheKey(userID:serverAddress:)` is what an avatar is stored under: the user and the server together, so two accounts on different instances never read each other's pictures.
    private static func cacheKey(userID: String, serverAddress: URL) -> String {
        "avatar:\(serverAddress.absoluteString):\(userID)"
    }
}
