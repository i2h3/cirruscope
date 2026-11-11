// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

extension Logger {
    /// `init(for:)` creates a logger for `type`, using the main bundle identifier as the subsystem and `type`'s unqualified name as the category.
    nonisolated init(for type: Any.Type) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "de.i2h3.cirruscope", category: String(describing: type))
    }
}
