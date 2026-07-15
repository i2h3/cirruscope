// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import os

/// `AssetCache` downloads remote assets into the app's caches directory and avoids redundant downloads by revalidating cached copies with the server using their HTTP `ETag`.
///
/// `Settings.persist(theming:)` uses the `shared` instance to keep local copies of the Nextcloud server's branding assets up to date so they can be displayed without re-fetching them every launch.
/// Cached files are addressed by the SHA-256 digest of their absolute URL so that distinct remote URLs map to distinct local files.
final class AssetCache: Sendable {
    /// `shared` is the process-wide cache instance.
    ///
    /// `Settings.persist(theming:)` uses it to cache the server's branding assets, and other parts of the app read those cached files back via `localURL(for:)`.
    static let shared = AssetCache()

    /// `logger` records asset caching activity under the `AssetCache` category.
    private let logger = Logger(for: AssetCache.self)

    /// `directory` is the on-disk location, rooted in the app's caches directory, in which cached asset payloads and their `ETag` sidecars are stored.
    private let directory: URL

    /// `session` is the `URLSession` used to download assets.
    private let session: URLSession

    /// `init()` creates the cache and ensures its on-disk directory exists.
    ///
    /// The directory is the `Assets` subdirectory of the app's caches directory and is created on first use.
    init() {
        directory = URL.cachesDirectory.appending(component: "Assets", directoryHint: .isDirectory)
        session = .shared

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Cache directory ready")
        } catch {
            logger.error("Could not create cache directory: \(error.localizedDescription)")
        }
    }

    /// `clear()` removes every cached payload and `ETag` sidecar stored by this cache.
    ///
    /// `Settings.serverAddress` invokes this when the user disconnects from the server so that no branding assets remain on disk that describe a server the app no longer talks to.
    func clear() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.debug("Could not remove cache directory (it may not exist yet): \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Cleared cache directory")
        } catch {
            logger.error("Could not recreate cache directory: \(error.localizedDescription)")
        }
    }

    /// `localURL(for:)` returns the file system URL of the cached copy of `remoteURL`, or `nil` if no copy has been downloaded yet.
    ///
    /// Call this from UI code that wants to display a cached asset; if it returns `nil`, the asset has not been downloaded yet and a placeholder should be shown instead.
    func localURL(for remoteURL: URL) -> URL? {
        let fileURL = fileURL(for: remoteURL)

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            logger.debug("Cache miss for \(remoteURL)")
            return nil
        }

        logger.debug("Cache hit for \(remoteURL)")
        return fileURL
    }

    /// `cache(remote:)` downloads the asset at `remoteURL` into the cache directory, unless the server confirms via the `ETag` sent in `If-None-Match` that the cached copy is still up to date.
    ///
    /// Returns the file system URL of the cached copy.
    /// Throws `CirruscopeError.invalidResponse` if the server response is not HTTP, `CirruscopeError.unexpectedStatus` for HTTP status codes outside 2xx and 304, and any error thrown by `URLSession` while transporting the request.
    @discardableResult
    func cache(remote remoteURL: URL) async throws -> URL {
        let fileURL = fileURL(for: remoteURL)

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)), let etag = etag(for: fileURL) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            logger.debug("Revalidating cached asset with stored ETag")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Non-HTTP response caching \(remoteURL)")
            throw CirruscopeError.invalidResponse
        }

        switch httpResponse.statusCode {
            case 304:
                logger.debug("Asset not modified (HTTP 304); using cached copy")
                return fileURL
            case 200 ..< 300:
                try data.write(to: fileURL, options: .atomic)
                if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                    setETag(newETag, for: fileURL)
                } else {
                    removeETag(for: fileURL)
                }
                logger.info("Cached asset (HTTP \(httpResponse.statusCode))")
                return fileURL
            default:
                logger.error("Unexpected status \(httpResponse.statusCode) caching asset")
                throw CirruscopeError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    /// `fileURL(for:)` returns the file system URL at which the cached copy of `remoteURL` is stored.
    ///
    /// The file name is the lowercase hex-encoded SHA-256 digest of `remoteURL.absoluteString` so that the mapping is deterministic and collision resistant.
    private func fileURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
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
