// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Darwin
import Foundation
import Testing

/// `QuarantineRemovalTests` covers `DownloadManager.removeQuarantine(from:)`, which replaces a `WKDownload`'s output with an app-written copy so the quarantine record's AppSandbox bit (`0x04`, which Gatekeeper refuses to exec or open) is gone, issue #149.
/// It reads the raw `com.apple.quarantine` record through `getxattr` rather than `URLResourceValues.quarantineProperties`, so the suite measures the attribute itself and not the same API the copy is checked with.
/// A sandboxed app cannot write the `0x04` bit itself, so the suite sets a web-download record (`0083`) via the LaunchServices API and asserts the replacement leaves only the app's own creation marker (`0082`); what matters is that no download-originated record survives on the file the app ends up with.
struct QuarantineRemovalTests {
    /// `quarantineFlags(_:)` returns the raw `com.apple.quarantine` record's leading four-byte flag field on `url` as a hex number, or `nil` when the record is absent.
    private func quarantineFlags(_ url: URL) -> UInt32? {
        let size = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0)
        guard size >= 4 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(url.path, "com.apple.quarantine", &buffer, buffer.count, 0, 0)
        guard read >= 4 else {
            return nil
        }
        return UInt32(String(bytes: buffer.prefix(4), encoding: .ascii) ?? "", radix: 16)
    }

    /// `quarantinedDownload()` writes a fresh uniquely named file in the user's Downloads folder, where the app's downloads entitlement applies, and stamps a web-download quarantine record on it the way a `WKDownload` arrives.
    private func quarantinedDownload() throws -> URL {
        var url = URL.downloadsDirectory.appendingPathComponent("cirruscope-quarantine-test-\(UUID().uuidString)")
        try "test".write(to: url, atomically: true, encoding: .utf8)

        var values = URLResourceValues()
        values.quarantineProperties = ["LSQuarantineTypeKey": "LSQuarantineTypeWebDownload", "LSQuarantineDataURLKey": "https://cloud.example.com/app.app"]
        try url.setResourceValues(values)

        return url
    }

    @Test
    func `A quarantined download ends up with only the app's own creation marker`() throws {
        let url = try quarantinedDownload()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(quarantineFlags(url) == 0x83)
        DownloadManager.removeQuarantine(from: url)
        #expect(quarantineFlags(url) == 0x82)
    }

    @Test
    func `A download stays intact when it is replaced by the app-written copy`() throws {
        let url = try quarantinedDownload()
        defer { try? FileManager.default.removeItem(at: url) }

        DownloadManager.removeQuarantine(from: url)
        #expect(quarantineFlags(url) == 0x82)
        #expect(try String(contentsOf: url, encoding: .utf8) == "test")
    }
}
