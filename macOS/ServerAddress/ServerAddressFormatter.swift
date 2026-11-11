// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAddressFormatter` is the `Formatter` `ServerAddressViewController` attaches to `serverAddressField` so that whatever the user typed is rewritten to `ServerAddress`' canonical form the moment editing ends — pressing Return, tabbing out of the field, or clicking elsewhere — instead of being canonicalized out of sight inside `open(_:)`.
final class ServerAddressFormatter: Formatter {
    /// `string(for:)` renders the cell's object value for display and for the field editor when editing begins.
    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    /// `getObjectValue(_:for:errorDescription:)` canonicalizes `string` through `ServerAddress` and hands the result back as the cell's object value, or hands back the input unchanged when it cannot be normalized.
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard let address = try? ServerAddress(normalizing: string) else {
            obj?.pointee = string as NSString

            return true
        }

        obj?.pointee = address.displayString as NSString

        return true
    }
}
