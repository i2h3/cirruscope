import CryptoKit
import Foundation

/// `AssetCache` downloads remote assets into the app's caches directory and avoids redundant downloads by revalidating cached copies with the server using their HTTP `ETag`.
///
/// `Settings.persist(theming:)` uses the `shared` instance to keep local copies of the Nextcloud server's branding assets up to date so they can be displayed without re-fetching them every launch.
/// Cached files are addressed by the SHA-256 digest of their absolute URL so that distinct remote URLs map to distinct local files.
final class AssetCache {

    /// `shared` is the process-wide cache instance.
    ///
    /// `Settings.persist(theming:)` uses it to cache the server's branding assets, and other parts of the app read those cached files back via `localURL(for:)`.
    static let shared = AssetCache()

    /// `directory` is the on-disk location, rooted in the app's caches directory, in which cached asset payloads and their `ETag` sidecars are stored.
    private let directory: URL

    /// `session` is the `URLSession` used to download assets.
    private let session: URLSession

    /// `init()` creates the cache and ensures its on-disk directory exists.
    ///
    /// The directory is the `Assets` subdirectory of the app's caches directory and is created on first use.
    init() {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = cachesDirectory.appendingPathComponent("Assets", isDirectory: true)
        session = .shared
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `clear()` removes every cached payload and `ETag` sidecar stored by this cache.
    ///
    /// `Settings.serverAddress` invokes this when the user disconnects from the server so that no branding assets remain on disk that describe a server the app no longer talks to.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `localURL(for:)` returns the file system URL of the cached copy of `remoteURL`, or `nil` if no copy has been downloaded yet.
    ///
    /// Call this from UI code that wants to display a cached asset; if it returns `nil`, the asset has not been downloaded yet and a placeholder should be shown instead.
    func localURL(for remoteURL: URL) -> URL? {
        let fileURL = fileURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    /// `cache(remote:)` downloads the asset at `remoteURL` into the cache directory, unless the server confirms via the `ETag` sent in `If-None-Match` that the cached copy is still up to date.
    ///
    /// Returns the file system URL of the cached copy.
    /// Throws `FramecloudError.invalidResponse` if the server response is not HTTP, `FramecloudError.unexpectedStatus` for HTTP status codes outside 2xx and 304, and any error thrown by `URLSession` while transporting the request.
    @discardableResult
    func cache(remote remoteURL: URL) async throws -> URL {
        let fileURL = fileURL(for: remoteURL)

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)), let etag = etag(for: fileURL) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FramecloudError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 304:
            return fileURL
        case 200..<300:
            try data.write(to: fileURL, options: .atomic)
            if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                setETag(newETag, for: fileURL)
            } else {
                removeETag(for: fileURL)
            }
            return fileURL
        default:
            throw FramecloudError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    /// `fileURL(for:)` returns the file system URL at which the cached copy of `remoteURL` is stored.
    ///
    /// The file name is the lowercase hex-encoded SHA-256 digest of `remoteURL.absoluteString` so that the mapping is deterministic and collision resistant.
    private func fileURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
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
