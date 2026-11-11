// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import os
import Rainmaker
import Synchronization

/// `ServerAvatars` keeps the profile photograph of every Nextcloud user the app has drawn a circle for, and hands one over as a bitmap whenever a row is being built.
final class ServerAvatars: Sendable {
    /// `shared` is the process-wide store of user avatars.
    static let shared = ServerAvatars()

    /// `cache` is where the photographs themselves live on disk.
    private let cache: AssetCache

    /// `decoded` holds the bitmaps already produced, keyed by the user and server they were produced for.
    private let decoded = Mutex<[String: CGImage]>([:])

    /// `withoutPhotograph` remembers which users the server answered for with a generated monogram, so the same answer is not fetched again for the life of the process.
    private let withoutPhotograph = Mutex<Set<String>>([])

    /// `logger` records avatar fetching and decoding under the `ServerAvatars` category.
    private let logger = Logger(for: ServerAvatars.self)

    /// `init(cache:)` creates a store over `cache`, which defaults to the process-wide one.
    init(cache: AssetCache = .shared) {
        self.cache = cache
    }

    /// `image(forUserID:serverAddress:size:)` is the photograph of one user at `size` as a bitmap, or `nil` when they have none, it has not been fetched at that size, or it cannot be decoded.
    func image(forUserID userID: String, serverAddress: URL, size: AvatarSize = .small) -> CGImage? {
        let key = Self.cacheKey(userID: userID, serverAddress: serverAddress, size: size)

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

    /// `refresh(userIDs:size:on:askingAgain:)` fetches the avatar of each named user at `size` that has not already been answered for, or of each named user when `askingAgain` is set, storing the photographs and remembering who has none.
    func refresh(userIDs: some Sequence<String>, size: AvatarSize = .small, on server: Server, askingAgain: Bool = false) async {
        let serverAddress = server.address

        for userID in Set(userIDs) {
            let key = Self.cacheKey(userID: userID, serverAddress: serverAddress, size: size)

            if askingAgain == false, withoutPhotograph.withLock({ $0.contains(key) }) {
                continue
            }

            do {
                let avatar = try await server.userAvatar(userID, size: size, darkTheme: false)

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
                logger.notice("Could not fetch the avatar of a user: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// `forget(userIDs:serverAddress:size:)` removes what is cached about the named users of the server at `serverAddress` at `size`: their photographs on disk, the bitmaps decoded from them, and any remembered absence.
    ///
    /// It is for a refresh a sign-out overtook, whose photographs may have landed after the sign-out emptied the cache; removing only what that refresh asked for leaves alone whatever an account signed in since has cached.
    func forget(userIDs: some Sequence<String>, serverAddress: URL, size: AvatarSize = .small) {
        for userID in Set(userIDs) {
            let key = Self.cacheKey(userID: userID, serverAddress: serverAddress, size: size)
            cache.remove(forKey: key)
            decoded.withLock { $0[key] = nil }
            withoutPhotograph.withLock { _ = $0.remove(key) }
        }
    }

    /// `clear()` drops every decoded bitmap and every remembered absence, for a sign-out.
    func clear() {
        decoded.withLock { $0.removeAll() }
        withoutPhotograph.withLock { $0.removeAll() }
    }

    /// `cacheKey(userID:serverAddress:size:)` is what an avatar is stored under: the user and the server together, so two accounts on different instances never read each other's pictures, and the size, so a refresh at one size never replaces or answers for the other.
    ///
    /// Photographs cached before the size was part of the key are no longer read and stay on disk until the next sign-out empties the cache.
    private static func cacheKey(userID: String, serverAddress: URL, size: AvatarSize) -> String {
        "avatar:\(serverAddress.absoluteString):\(userID):\(size.rawValue)"
    }
}
