// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebWindowFrameTests` covers `WebWindowFrame`, which remembers how large the user last made a web window so the next one opens at that size (issue #82).
@MainActor
@Suite(.serialized)
struct WebWindowFrameTests {
    /// `removeStoredFrame(named:)` deletes the `UserDefaults` entry AppKit keeps a named frame in, returning the domain to the state a machine that had never saved that name would be in.
    private func removeStoredFrame(named name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    /// `makeWindow(frame:)` builds a titled, resizable, closable window at `frame`, matching the style mask the storyboard's "Web Window" scene declares.
    private func makeWindow(frame: NSRect) -> NSWindow {
        NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    }

    @Test(arguments: [
        // The storyboard's own mask for the web window, and the same mask once macOS has taken it fullscreen.
        (NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]), true),
        (NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .fullScreen]), false),
        // A bare mask either way, so the rule is shown to turn on `.fullScreen` alone rather than on any of its company.
        (NSWindow.StyleMask([.borderless]), true),
        (NSWindow.StyleMask([.fullScreen]), false),
    ])
    func `A frame is worth remembering unless the window is in fullscreen`(styleMask: NSWindow.StyleMask, isRecordable: Bool) {
        #expect(WebWindowFrame.isRecordable(styleMask: styleMask) == isRecordable)
    }

    @Test
    func `A recorded size is applied to a later window while its position is left alone`() {
        let name = "WebWindowFrameTests.RoundTrip"
        removeStoredFrame(named: name)
        defer { removeStoredFrame(named: name) }

        let recorded = makeWindow(frame: NSRect(x: 120, y: 140, width: 900, height: 650))
        WebWindowFrame.record(recorded, name: name)

        // A second, separately created window, so what is measured is the frame actually making it through
        // `UserDefaults` and back rather than anything the first window still holds in memory.
        let applied = makeWindow(frame: NSRect(x: 300, y: 320, width: 1200, height: 800))
        let originBeforeApplying = applied.frame.origin
        WebWindowFrame.applySize(to: applied, name: name)

        #expect(applied.frame.size == recorded.frame.size)
        #expect(applied.frame.origin == originBeforeApplying)
    }

    @Test
    func `A window keeps its storyboard size while no size has been remembered`() {
        let name = "WebWindowFrameTests.NothingRemembered"
        removeStoredFrame(named: name)
        defer { removeStoredFrame(named: name) }

        let window = makeWindow(frame: NSRect(x: 300, y: 320, width: 1200, height: 800))
        let frameBeforeApplying = window.frame
        WebWindowFrame.applySize(to: window, name: name)

        #expect(window.frame == frameBeforeApplying)
    }
}
