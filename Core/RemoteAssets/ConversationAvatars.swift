// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import os
import Rainmaker
import Synchronization

/// `ConversationAvatars` keeps the picture Nextcloud Talk draws for each of the account's conversations, so a Spotlight result can wear the face of the person it opens rather than the app's mark.
///
/// It is the third of these stores and follows `ServerAvatars` in shape — cached on disk under a key built from what the picture *is of* rather than from where it came from, read synchronously because the caller is building something that is about to be drawn, and answering `nil` as an ordinary result rather than a failure.
///
/// Two things make it its own type rather than a second method on `ServerAvatars`. The first is what the server sends: a conversation's picture may be a photograph a moderator uploaded, the other person's avatar, an emoji, or an icon the server generates, and the last two commonly arrive as **SVG** — which neither platform decodes and which `Core/RemoteAssets/SVG/` deliberately reads only far enough for the monochrome app glyphs. Those are skipped rather than approximated, and skipping them is what leaves the Talk mark in place, which is a correct picture rather than a wrong one.
/// The second is the key. Rainmaker states outright that a conversation's avatar version is not enough on its own — for a one-to-one conversation the server derives it from the path of a generic icon, so it is identical for every such conversation and never moves when the other person changes their photograph. The key therefore carries the server, the account, the token, the version and the appearance, and the account is in it because a one-to-one picture is of *the other party*, which is a different person depending on who is signed in.
final class ConversationAvatars: Sendable {
    /// `shared` is the process-wide store of conversation avatars.
    static let shared = ConversationAvatars()

    /// `cache` is where the pictures themselves live on disk.
    private let cache: AssetCache

    /// `decoded` holds the bitmaps already produced, keyed exactly as the files are.
    ///
    /// A `Mutex` rather than an actor for the reason the sibling stores use one: the readers cannot `await`, being on the path that builds an entity the moment it is asked for.
    private let decoded = Mutex<[String: CGImage]>([:])

    /// `undrawable` remembers which pictures the server answered with something this cannot decode, so the same answer is not fetched again for the life of the process.
    ///
    /// Without it, every refresh would re-request a picture for every conversation the server draws itself, which on an account whose conversations are mostly groups is most of them. It is deliberately not persisted: a moderator uploading a photograph should see it appear, and a process ending is the bound on how long this can be wrong.
    private let undrawable = Mutex<Set<String>>([])

    /// `logger` records fetching and decoding under the `ConversationAvatars` category.
    private let logger = Logger(for: ConversationAvatars.self)

    /// `drawableContentTypes` are the two answers this can turn into a bitmap.
    ///
    /// An allow list rather than a list of what to reject, so a type nobody has seen yet is skipped rather than handed to a decoder that will answer `nil` anyway — and so the log says which type it was.
    private static let drawableContentTypes: Set<String> = ["image/png", "image/jpeg"]

    /// `init(cache:)` creates a store over `cache`, which defaults to the process-wide one.
    init(cache: AssetCache = .shared) {
        self.cache = cache
    }

    /// `image(forToken:avatarVersion:accountName:serverAddress:)` is one conversation's picture as a bitmap, or `nil` when none has been cached or it cannot be decoded.
    ///
    /// A `nil` is the ordinary answer rather than a failure: nothing has been fetched on a first launch, and a conversation the server draws itself never gets one cached at all. Either way the caller falls back to the Talk mark.
    func image(forToken token: String, avatarVersion: String, accountName: String, serverAddress: URL) -> CGImage? {
        let key = Self.cacheKey(token: token, avatarVersion: avatarVersion, accountName: accountName, serverAddress: serverAddress)

        if let existing = decoded.withLock({ $0[key] }) {
            return existing
        }

        guard let data = cache.data(forKey: key) else {
            return nil
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            logger.notice("The picture cached for a conversation is not an image source this can read")
            return nil
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger.notice("The picture cached for a conversation could not be decoded")
            return nil
        }

        decoded.withLock { $0[key] = image }

        return image
    }

    /// `refresh(conversations:accountName:on:)` fetches the picture of each conversation that has not already been answered for, and reports whether anything new landed.
    ///
    /// The caller announces the conversations again when this answers `true`, which is what puts the pictures into Spotlight without waiting for the next launch — the same arrangement the server apps' icons already use, and for the same reason: the list is worth having before the pictures are, so it is persisted first.
    /// Fetches run one after another rather than concurrently, matching `ServerAvatars`: this is background work feeding a search index, and opening a socket per conversation would be the app taking more than it is owed for it.
    /// Nothing is thrown. A picture that cannot be fetched leaves the cache as it was, and the caller draws the Talk mark, which is the same outcome as a conversation the server has no bitmap for.
    @discardableResult
    func refresh(conversations: [(token: String, avatarVersion: String)], accountName: String, on server: Server) async -> Bool {
        let serverAddress = server.address
        var didFetchAny = false

        for conversation in conversations {
            let key = Self.cacheKey(token: conversation.token, avatarVersion: conversation.avatarVersion, accountName: accountName, serverAddress: serverAddress)

            if undrawable.withLock({ $0.contains(key) }) {
                continue
            }

            if cache.data(forKey: key) != nil {
                continue
            }

            do {
                // The light variant only. The artwork donated to Spotlight is opaque precisely so that one
                // bitmap is right in both appearances, so a second fetch for the dark one would be a request
                // per conversation for a picture nothing would ever draw.
                let avatar = try await server.conversationAvatar(conversation.token, darkTheme: false)

                guard Self.drawableContentTypes.contains(avatar.contentType.lowercased()) else {
                    logger.notice("A conversation's picture arrived as \(avatar.contentType, privacy: .public), which this does not decode; leaving the Talk mark in place for it")
                    undrawable.withLock { _ = $0.insert(key) }
                    continue
                }

                cache.store(avatar.data, forKey: key)
                decoded.withLock { $0[key] = nil }
                didFetchAny = true

                logger.debug("Cached a conversation's picture as \(avatar.contentType, privacy: .public)")
            } catch {
                logger.notice("Could not fetch a conversation's picture: \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.notice("Refreshed the pictures of \(conversations.count, privacy: .public) conversation(s); \(didFetchAny ? "something new was cached" : "nothing new was cached", privacy: .public)")

        return didFetchAny
    }

    /// `clear()` drops every decoded bitmap and every remembered refusal, for a sign-out.
    ///
    /// The files themselves go with `AssetCache.clear()`, which runs beside this when an account is disconnected; this is what stops the ones already decoded from outliving them in memory, exactly as the sibling stores do.
    func clear() {
        decoded.withLock { $0.removeAll() }
        undrawable.withLock { $0.removeAll() }
    }

    /// `cacheKey(token:avatarVersion:accountName:serverAddress:)` is what one conversation's picture is stored under.
    ///
    /// Every part of it earns its place, and the two that look redundant are the ones that are not: the account, because a one-to-one conversation's picture is of the other party and so depends on who is signed in, and the version, because it is the only signal that a moderator changed a group's picture. Neither is sufficient alone, which is why both are here.
    private static func cacheKey(token: String, avatarVersion: String, accountName: String, serverAddress: URL) -> String {
        "conversation-avatar\u{1}\(serverAddress.absoluteString)\u{1}\(accountName)\u{1}\(token)\u{1}\(avatarVersion)\u{1}light"
    }
}
