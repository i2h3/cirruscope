// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectiveTransferObject` is a value-type snapshot of one collective the connected account is a member of.
struct CollectiveTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the collective's server-assigned identifier, which is what listing its pages takes.
    let id: Int

    /// `name` is the collective's human-readable name, which is also what its folder is called.
    let name: String

    /// `slug` is the url-safe form of `name` the server addresses the collective by in a link, or `nil` on a server whose Collectives app predates slugs.
    let slug: String?

    /// `emoji` is the emoji the collective is decorated with, or `nil` when it has none.
    let emoji: String?
}
