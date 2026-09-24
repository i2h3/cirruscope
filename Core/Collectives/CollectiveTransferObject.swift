// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectiveTransferObject` is a value-type snapshot of one collective the connected account is a member of.
///
/// It is the shape both apps pass around and the shape `AccountStore` is written with and read from, so nothing about the store's surface depends on the network library's own models — the same arrangement every other domain here has, and what lets a test seed collectives without either test target linking Rainmaker.
///
/// Three things the server reports are deliberately not here, and each for its own reason. `shareToken` is a capability: anyone holding it reads the collective without signing in, so it is the one field in this domain that would turn an unencrypted store into a credential store. `collectivePath` discloses where the collective's files sit in the account's own storage, which nothing in this feature needs and which names a hidden folder whose spelling depends on the account's locale. The permission flags and the membership level are left out as facts about what the user may do rather than about which collective this is, and nothing here does anything but find one and open it.
struct CollectiveTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the collective's server-assigned identifier, which is what listing its pages takes.
    let id: Int

    /// `name` is the collective's human-readable name, which is also what its folder is called.
    let name: String

    /// `slug` is the url-safe form of `name` the server addresses the collective by in a link, or `nil` on a server whose Collectives app predates slugs.
    ///
    /// Optional because that is a real state rather than missing data, and the route that opens a collective has to fall back to `name` when it is absent.
    let slug: String?

    /// `emoji` is the emoji the collective is decorated with, or `nil` when it has none.
    let emoji: String?
}
