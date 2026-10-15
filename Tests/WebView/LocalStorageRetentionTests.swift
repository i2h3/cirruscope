// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `LocalStorageRetentionTests` measures that `Script.localStorageRetention`, installed the way both apps install it, keeps a page's own call clearing local storage from removing anything.
///
/// Nextcloud's page script clears local storage whenever the web view's browser session lapses, and the app signs the same account straight back in, so without the script that clearing is all the user would notice of the lapse: the emoji picker's skin tone and every other preference kept there would be gone (issue #143).
/// The fix rests on a belief about WebKit, that a user script replacing the storage method at document start decides what the page's own later call does, so `LocalStorageClearProbe` loads a page making that call into a real `WKWebView` rather than this suite restating it.
/// The first case is the control that keeps the second honest: without the script the same page does empty its local storage, so an item surviving in the second is the script's doing and not the probe's.
/// The time limit turns an alert that never arrives into a failure rather than a run that never ends.
///
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct LocalStorageRetentionTests {
    @Test
    func `Without the script a page clearing its local storage empties it`() async {
        let remaining = await LocalStorageClearProbe.remainingItemCount(installing: nil)

        #expect(remaining == 0)
    }

    @Test
    func `With the script a page clearing its local storage keeps every item`() async throws {
        let source = try #require(Script.localStorageRetention.source)
        let remaining = await LocalStorageClearProbe.remainingItemCount(installing: source)

        #expect(remaining == 1)
    }
}
