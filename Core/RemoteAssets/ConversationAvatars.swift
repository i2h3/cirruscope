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

    /// `undrawable` remembers which pictures the server answered with something this cannot decode, so the same answer is not asked for again.
    ///
    /// Without it, every refresh would re-request a picture for every conversation the server draws itself, which on an account whose conversations are mostly groups is most of them. This is the in-process half; the durable half is a zero-length file under the same cache key, which is what carries the verdict across a launch — without it the whole account was re-asked on every launch, which is most of what made the first refresh slow.
    /// Neither is permanent, and that matters more than it sounds: the key holds the conversation's avatar version, so a moderator's new picture is a different key and the old verdict simply does not apply, and `freshness` bounds the case a version cannot describe.
    private let undrawable = Mutex<Set<String>>([])

    /// `logger` records fetching and decoding under the `ConversationAvatars` category.
    private let logger = Logger(for: ConversationAvatars.self)

    /// `drawableContentTypes` are the two answers this can turn into a bitmap.
    ///
    /// An allow list rather than a list of what to reject, so a type nobody has seen yet is skipped rather than handed to a decoder that will answer `nil` anyway — and so the log says which type it was.
    private static let drawableContentTypes: Set<String> = ["image/png", "image/jpeg"]

    /// `concurrentFetches` is how many of these requests are in flight at once.
    ///
    /// Six, which is what the transport would allow anyway: Rainmaker gives each server an ephemeral `URLSession`, whose `httpMaximumConnectionsPerHost` is six on macOS and four on iOS, so a wider window would only queue inside the session while making the app look greedier in the instance's access log than it is. It is also a number a Nextcloud serves without noticing, each of these being a few kilobytes — where a window the width of the conversation list would be a burst of dozens against a worker pool shared with everything else the user has open.
    private static let concurrentFetches = 6

    /// `freshness` is how long the server's last answer about a conversation is trusted before it is asked again.
    ///
    /// A bound is needed because the key cannot carry one for every kind of conversation. A group's avatar version moves the moment a moderator changes the picture, so the key invalidates itself; a one-to-one conversation's version is derived by the server from the path of a generic icon and never moves at all, so without a bound the other person's new photograph would never be asked for again. A week is long enough that a launch costs nothing and short enough that nobody's new picture is invisible for long.
    private static let freshness: TimeInterval = 7 * 24 * 60 * 60

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

        // Zero bytes is the recorded refusal rather than a broken file, and it has to be read as one here:
        // `CGImageSourceCreateWithData` answers an empty source rather than `nil` for it, so without this every
        // entity built for such a conversation would take the decode path and log a failure that is not one.
        guard data.isEmpty == false else {
            undrawable.withLock { _ = $0.insert(key) }
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
    /// Fetches run concurrently, a bounded number at a time, which `ServerAppIcons` already does for the icons and for the same reason: each of these is a few kilobytes, they are independent, and an account of forty conversations was otherwise paying forty round trips in a row for pictures nothing was waiting on in order — with the notes and the collectives queued behind all of them.
    /// `ServerAvatars` stays serial and is deliberately *not* the precedent here, though an earlier version of this file claimed it was. Its reason is written down and does not transfer: it runs in the widget extension, where opening a dozen sockets at once is not on, and its count is bounded by the rows a layout draws. This runs in the app, its count is the whole Talk list, and somebody is watching the results it feeds.
    /// Nothing is thrown. A picture that cannot be fetched leaves the cache as it was, and the caller draws the Talk mark, which is the same outcome as a conversation the server has no bitmap for.
    @discardableResult
    func refresh(conversations: [(token: String, avatarVersion: String)], accountName: String, on server: Server) async -> Bool {
        let serverAddress = server.address

        // Decided before anything starts, and on this task rather than inside the group: both of these read
        // shared state, and settling them here keeps every task that is started a request and nothing else.
        let pending: [(token: String, key: String)] = conversations.compactMap { conversation in
            let key = Self.cacheKey(token: conversation.token, avatarVersion: conversation.avatarVersion, accountName: accountName, serverAddress: serverAddress)

            if undrawable.withLock({ $0.contains(key) }) {
                return nil
            }

            if hasFreshAnswer(forKey: key) {
                return nil
            }

            return (token: conversation.token, key: key)
        }

        guard pending.isEmpty == false else {
            logger.notice("All \(conversations.count, privacy: .public) conversation(s) already had a fresh answer; nothing was fetched")
            return false
        }

        let didFetchAny = await withTaskGroup(of: Bool.self) { group in
            var next = 0
            var didFetchAny = false

            while next < min(Self.concurrentFetches, pending.count) {
                let conversation = pending[next]
                group.addTask { await self.fetch(token: conversation.token, storingUnder: conversation.key, on: server) }
                next += 1
            }

            // One finishes, one starts, so the window stays the same width for the whole run rather than
            // draining to nothing and refilling. The reduction happens here, on the group's own task, which is
            // why nothing shared is being written by anything that could be writing it at the same moment.
            while let didCache = await group.next() {
                didFetchAny = didFetchAny || didCache

                guard next < pending.count else {
                    continue
                }

                let conversation = pending[next]
                group.addTask { await self.fetch(token: conversation.token, storingUnder: conversation.key, on: server) }
                next += 1
            }

            return didFetchAny
        }

        logger.notice("Asked after \(pending.count, privacy: .public) of \(conversations.count, privacy: .public) conversation(s), \(Self.concurrentFetches, privacy: .public) at a time; \(didFetchAny ? "something new was cached" : "nothing new was cached", privacy: .public)")

        return didFetchAny
    }

    /// `fetch(token:storingUnder:on:)` is one conversation's request, and reports whether it left something new behind.
    ///
    /// A method rather than a closure written into the group, so what each task captures is spelled out: a token, a key, and the two `Sendable` things this type is made of.
    /// An answer this cannot decode is recorded as a zero-length file under the same key, which is what stops it being asked again on the next launch as well as on the next refresh.
    /// It answers `false` for bytes identical to the ones already cached, so that revalidating a picture a week later does not announce a change nothing can see — the caller turns a `true` into a Spotlight re-donation of the whole domain.
    private func fetch(token: String, storingUnder key: String, on server: Server) async -> Bool {
        do {
            // The light variant only. The artwork donated to Spotlight is opaque precisely so that one bitmap is
            // right in both appearances, so a second fetch for the dark one would be a request per conversation
            // for a picture nothing would ever draw.
            let avatar = try await server.conversationAvatar(token, darkTheme: false)

            guard Self.drawableContentTypes.contains(avatar.contentType.lowercased()) else {
                logger.notice("A conversation's picture arrived as \(avatar.contentType, privacy: .public), which this does not decode; recording that so it is not asked for again, and leaving the Talk mark in place for it")
                undrawable.withLock { _ = $0.insert(key) }
                cache.store(Data(), forKey: key)
                return false
            }

            let wasUnchanged = cache.data(forKey: key) == avatar.data
            cache.store(avatar.data, forKey: key)
            decoded.withLock { $0[key] = nil }

            logger.debug("Cached a conversation's picture as \(avatar.contentType, privacy: .public)")

            return wasUnchanged == false
        } catch {
            logger.notice("Could not fetch a conversation's picture: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `hasFreshAnswer(forKey:)` reports whether the server's last answer about `key` is recent enough to stand.
    ///
    /// An answer is a bitmap or the zero-length file recording one this cannot decode, and both age the same way. Asked by file date rather than by reading the bytes, so a refresh no longer reads every cached picture off disk only to learn it exists.
    /// A file whose date cannot be read counts as fresh rather than stale: the cost of being wrong that way is a picture a week out of date, and the cost of being wrong the other way is a request per conversation on every single refresh.
    private func hasFreshAnswer(forKey key: String) -> Bool {
        guard let fileURL = cache.localURL(forKey: key) else {
            return false
        }

        guard let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return true
        }

        return Date.now.timeIntervalSince(modified) < Self.freshness
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
