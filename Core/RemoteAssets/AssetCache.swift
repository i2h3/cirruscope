// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import os

/// `AssetCache` downloads remote assets into a caches directory, the shared App Group container's for `shared`, and avoids redundant downloads by revalidating cached copies with the server using their HTTP `ETag`.
final class AssetCache: Sendable {
    /// `shared` is the process-wide cache instance.
    static let shared = AssetCache()

    /// `logger` records asset caching activity under the `AssetCache` category.
    private let logger = Logger(for: AssetCache.self)

    /// `directory` is where cached asset payloads and their `ETag` sidecars are stored: the directory `assetsDirectory()` resolved for `init()`, or the one handed to `init(directory:)`.
    private let directory: URL

    /// `session` is the `URLSession` used to download assets.
    private let session: URLSession

    /// `init()` creates the cache over the directory `assetsDirectory()` resolved.
    init() {
        directory = Self.assetsDirectory()
        session = .shared
    }

    /// `init(directory:)` creates a cache over `directory`, which must already exist.
    init(directory: URL) {
        self.directory = directory
        session = .shared
    }

    /// `assetsDirectory()` is the directory cached payloads and their `ETag` sidecars live in, created if it does not exist yet.
    private static func assetsDirectory() -> URL {
        let logger = Logger(for: AssetCache.self)
        let directory = AppGroup.containerURL
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            .appending(component: "Assets", directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Cache directory ready in the App Group container")
        } catch {
            logger.fault("Could not create the cache directory in the App Group container: \(error.localizedDescription, privacy: .public)")
        }

        return directory
    }

    /// `clear()` removes every cached payload and `ETag` sidecar stored by this cache.
    func clear() {
        let contents: [URL]

        do {
            contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsSubdirectoryDescendants)
        } catch {
            logger.debug("Could not list the cache directory (it may not exist yet): \(error.localizedDescription)")
            return
        }

        var removed = 0

        for file in contents {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                logger.error("Could not remove a cached asset: \(error.localizedDescription)")
            }
        }

        logger.debug("Cleared \(removed) cached asset(s)")
    }

    /// `localURL(for:)` returns the file system URL of the cached copy of `remoteURL`, or `nil` if no copy has been downloaded yet.
    func localURL(for remoteURL: URL) -> URL? {
        localURL(forKey: remoteURL.absoluteString)
    }

    /// `localURL(forKey:)` returns the file system URL of the copy cached under `key`, or `nil` if none has been downloaded yet.
    ///
    /// A caller that knows what it is looking for before it knows where that came from uses this. Server app icons are the case in point: the menus have an app's identifier at launch but not the path the server will next say its icon lives at, so they are cached under a key built from the two things a menu does hold, and found again without the network having been reached.
    func localURL(forKey key: String) -> URL? {
        let fileURL = fileURL(forKey: key)

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            logger.debug("Cache miss for \(key, privacy: .public)")
            return nil
        }

        logger.debug("Cache hit for \(key, privacy: .public)")
        return fileURL
    }

    /// `data(forKey:)` is the bytes cached under `key`, or `nil` if nothing is cached or they cannot be read.
    func data(forKey key: String) -> Data? {
        guard let fileURL = localURL(forKey: key) else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    /// `store(_:forKey:)` writes bytes this cache did not fetch itself under `key`, replacing whatever was there.
    func store(_ data: Data, forKey key: String) {
        let fileURL = fileURL(forKey: key)

        do {
            try data.write(to: fileURL, options: .atomic)
            removeETag(for: fileURL)
            logger.info("Stored \(data.count) externally fetched byte(s) for \(key, privacy: .public)")
        } catch {
            logger.error("Could not store externally fetched bytes for \(key, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// `remove(forKey:)` deletes the copy cached under `key`, along with its `ETag`, if either exists.
    ///
    /// A caller that learns an asset it cached is no longer the right one to show uses this — an account whose avatar stopped being a photograph and became a generated monogram, for instance, where leaving the old file in place would keep showing a picture the user has since removed.
    func remove(forKey key: String) {
        let fileURL = fileURL(forKey: key)

        try? FileManager.default.removeItem(at: fileURL)
        removeETag(for: fileURL)
    }

    /// `cache(remote:)` downloads the asset at `remoteURL` into the cache directory, unless the server confirms via the `ETag` sent in `If-None-Match` that the cached copy is still up to date.
    @discardableResult
    func cache(remote remoteURL: URL) async throws -> URL {
        try await cache(remote: remoteURL, key: nil, authenticatedAs: nil)
    }

    /// `cache(remote:key:authenticatedAs:)` downloads the asset at `remoteURL`, storing it under `key` and identifying the user with `credentials`.
    @discardableResult
    func cache(remote asset: SameOriginURL, key: String? = nil, authenticatedAs credentials: Credentials? = nil) async throws -> URL {
        try await cache(remote: asset.url, key: key, authenticatedAs: credentials)
    }

    /// `cache(remote:key:authenticatedAs:)` is the transfer itself, shared by the two entry points above.
    @discardableResult
    private func cache(remote remoteURL: URL, key: String?, authenticatedAs credentials: Credentials?) async throws -> URL {
        let fileURL = fileURL(forKey: key ?? remoteURL.absoluteString)
        let localETag = etag(for: fileURL)

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let credentials {
            request.setValue(credentials.basicAuthorizationValue, forHTTPHeaderField: "Authorization")
        }

        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)), let localETag {
            request.setValue(localETag, forHTTPHeaderField: "If-None-Match")
            logger.debug("Revalidating \(remoteURL, privacy: .public) with locally cached ETag \(localETag, privacy: .public)")
        } else {
            logger.debug("Requesting \(remoteURL, privacy: .public) unconditionally; no locally cached ETag")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Non-HTTP response caching \(remoteURL, privacy: .public)")
            throw CirruscopeError.invalidResponse
        }

        let serverETag = httpResponse.value(forHTTPHeaderField: "ETag") ?? "none"

        switch httpResponse.statusCode {
            case 304:
                logger.debug("Asset not modified (HTTP 304) for \(remoteURL, privacy: .public); server ETag \(serverETag, privacy: .public)")
                return fileURL
            case 200 ..< 300:
                try data.write(to: fileURL, options: .atomic)
                if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                    setETag(newETag, for: fileURL)
                } else {
                    removeETag(for: fileURL)
                }
                logger.info("Cached asset (HTTP \(httpResponse.statusCode)) for \(remoteURL, privacy: .public); server ETag \(serverETag, privacy: .public)")
                return fileURL
            default:
                logger.error("Unexpected status \(httpResponse.statusCode) caching \(remoteURL, privacy: .public)")
                throw CirruscopeError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    /// `fileURL(forKey:)` returns the file system URL at which the copy cached under `key` is stored.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(component: name)
    }

    /// `etagURL(for:)` returns the file system URL of the `ETag` sidecar file that accompanies the cached payload at `fileURL`.
    private func etagURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("etag")
    }

    /// `etag(for:)` reads the `ETag` previously persisted alongside the cached payload at `fileURL`, or returns `nil` if none has been recorded.
    private func etag(for fileURL: URL) -> String? {
        try? String(contentsOf: etagURL(for: fileURL), encoding: .utf8)
    }

    /// `setETag(_:for:)` persists `etag` alongside the cached payload at `fileURL` so subsequent downloads can revalidate the cached copy.
    private func setETag(_ etag: String, for fileURL: URL) {
        try? etag.write(to: etagURL(for: fileURL), atomically: true, encoding: .utf8)
    }

    /// `removeETag(for:)` deletes the `ETag` sidecar for `fileURL`, if one exists, so that the next download is unconditional.
    private func removeETag(for fileURL: URL) {
        try? FileManager.default.removeItem(at: etagURL(for: fileURL))
    }
}
