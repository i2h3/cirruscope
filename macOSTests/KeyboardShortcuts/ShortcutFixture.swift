// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope

/// `ShortcutFixture` is one named keyboard shortcut the shortcut test suites run their cases over.
struct ShortcutFixture: Sendable, CustomStringConvertible {
    /// `name` is the symbolic spelling of the shortcut, used as the fixture's description in test output.
    let name: String

    /// `shortcut` is the fixture's value as the app stores and compares it.
    let shortcut: KeyboardShortcutTransferObject

    var description: String {
        name
    }

    private init(_ name: String, _ keyEquivalent: String, _ modifiers: NSEvent.ModifierFlags) {
        self.name = name
        shortcut = KeyboardShortcutTransferObject(keyEquivalent: keyEquivalent, modifierFlags: modifiers.rawValue)
    }

    /// `f5` is the Private Use Area scalar AppKit reserves for F5 (`NSF5FunctionKey`), which is what a recorded F5 stores as its key equivalent.
    private static let f5 = "\u{F708}"

    /// `arrowUp` is the Private Use Area scalar AppKit reserves for the up arrow key (`NSUpArrowFunctionKey`).
    private static let arrowUp = "\u{F700}"

    /// `all` is every combination the suites cover: the case-carrying keys where Shift lives in the character, the shift-invariant typable keys, and the function-region keys where Shift lives in the modifier mask.
    static let all: [ShortcutFixture] = [
        .init("⌘z", "z", [.command]),
        .init("⌘Z", "Z", [.command]),
        .init("⇧⌘Z", "Z", [.command, .shift]),
        .init("⌥⌘z", "z", [.command, .option]),
        .init("⌃⌘z", "z", [.command, .control]),
        .init("⌘1", "1", [.command]),
        .init("⌘!", "!", [.command]),
        .init("⇧⌘!", "!", [.command, .shift]),
        .init("⌘⇥", "\t", [.command]),
        .init("⇧⌘⇥", "\t", [.command, .shift]),
        .init("⌘space", " ", [.command]),
        .init("⇧⌘space", " ", [.command, .shift]),
        .init("F5", f5, []),
        .init("⇧F5", f5, [.shift]),
        .init("⌘F5", f5, [.command]),
        .init("⇧⌘F5", f5, [.command, .shift]),
        .init("↑", arrowUp, []),
        .init("⇧↑", arrowUp, [.shift]),
    ]

    /// `named(_:)` is the fixture called `name`, for a case that needs one specific combination rather than the whole corpus.
    static func named(_ name: String) -> ShortcutFixture {
        guard let fixture = all.first(where: { $0.name == name }) else {
            preconditionFailure("No shortcut fixture named \(name)")
        }

        return fixture
    }
}
