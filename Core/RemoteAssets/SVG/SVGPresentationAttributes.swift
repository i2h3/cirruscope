// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SVGPresentationAttributes` answers what one SVG element says about how it should be painted, whether it says it as an attribute or inside a `style` declaration.
struct SVGPresentationAttributes {
    /// `attributes` are the element's attributes exactly as the parser reported them.
    private let attributes: [String: String]

    /// `declarations` are the properties parsed out of the element's `style` attribute, keyed by property name.
    private let declarations: [String: String]

    /// `init(_:)` reads `attributes`, splitting any `style` among them into its declarations.
    init(_ attributes: [String: String]) {
        self.attributes = attributes

        guard let style = attributes["style"] else {
            declarations = [:]
            return
        }

        var declarations: [String: String] = [:]

        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)

            guard parts.count == 2 else {
                continue
            }

            declarations[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.declarations = declarations
    }

    /// `value(_:)` is what the element says `property` is, or `nil` if it says nothing about it.
    func value(_ property: String) -> String? {
        declarations[property] ?? attributes[property]
    }

    /// `number(_:)` is `value(_:)` read as a number, or `nil` if it is absent or not one.
    func number(_ property: String) -> Double? {
        guard let text = value(property) else {
            return nil
        }

        var scanner = SVGNumberScanner(text)

        return scanner.nextNumber()
    }
}
