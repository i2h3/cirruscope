// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `KeyEquivalentMatchingOracleTests` checks `ShortcutMatching.areEquivalent(_:_:)` against real AppKit rather than against the app's beliefs about it, by comparing every pair of `ShortcutFixture.all` with what `KeyEquivalentProbe` measures.
@MainActor
@Suite(.serialized)
struct KeyEquivalentMatchingOracleTests {
    @Test(arguments: ShortcutFixture.all, ShortcutFixture.all)
    func `areEquivalent agrees with NSMenu key-equivalent matching`(pressed: ShortcutFixture, declared: ShortcutFixture) {
        let predicted = ShortcutMatching.areEquivalent(pressed.shortcut, declared.shortcut)
        let actual = KeyEquivalentProbe.fires(keystroke: pressed.shortcut, againstItemDeclaring: declared.shortcut)

        #expect(predicted == actual, "pressing \(pressed) against a menu item declaring \(declared): areEquivalent said \(predicted), AppKit \(actual ? "fired the item" : "did not fire the item")")
    }

    @Test
    func `The probe can tell a match from a miss`() {
        // Guards the oracle itself: were every probe to answer `false` — an item AppKit considers disabled never
        // performs its key equivalent — the comparison above would agree with nothing and still pass.
        #expect(KeyEquivalentProbe.fires(keystroke: ShortcutFixture.named("⌘z").shortcut, againstItemDeclaring: ShortcutFixture.named("⌘z").shortcut))
        #expect(KeyEquivalentProbe.fires(keystroke: ShortcutFixture.named("⌘z").shortcut, againstItemDeclaring: ShortcutFixture.named("⌘1").shortcut) == false)
    }
}
