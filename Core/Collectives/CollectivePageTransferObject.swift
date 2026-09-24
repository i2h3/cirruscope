// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `CollectivePageTransferObject` is a value-type snapshot of one page within a collective.
///
/// It carries what it takes to find a page and to address it, and no more. The page's Markdown is not here and is not fetched: the server's page listing is metadata only, and the text lives in a file in the collective's folder that this app never reads — which makes the note-text question this domain's non-question, since there is nothing to decline to store.
///
/// What is deliberately dropped is who last edited the page. The server reports an editor's account name and display name on every page, and that is a record of *other people's* activity kept in an unencrypted file on this device, for a feature that only finds pages and opens them. `collectivePath` is dropped for the same kind of reason it is on a collective: it discloses storage layout nothing here needs.
struct CollectivePageTransferObject: Codable, Identifiable, Hashable, Sendable {
    /// `id` is the page's server-assigned identifier, which is the identifier of its file.
    let id: Int

    /// `collectiveID` is the identifier of the collective this page belongs to.
    ///
    /// Carried on the snapshot rather than left implicit in the relationship, because addressing a page means addressing it *within* a collective: the route needs the collective's own segment in front of the page's.
    let collectiveID: Int

    /// `title` is the page's title, which for an ordinary page is its file name without the Markdown extension.
    ///
    /// The page at the root of a collective is the exception: the server substitutes a localized title there, so it reads in the language of the account rather than matching the file.
    let title: String

    /// `slug` is the url-safe form of `title` the server addresses the page by in a link, or `nil` on a server whose Collectives app predates slugs.
    let slug: String?

    /// `emoji` is the emoji the page is decorated with, or `nil` when it has none.
    let emoji: String?

    /// `fileName` is the name of the file backing the page, including its extension.
    ///
    /// A page that has subpages is stored as the index file of a folder and is therefore always called `Readme.md`, which is what makes `fileName` alone insufficient to address a page and why `filePath` is carried beside it.
    let fileName: String

    /// `filePath` is the folder containing `fileName`, relative to the root of the collective, or an empty string for a page sitting directly in it.
    let filePath: String

    /// `isLandingPage` is whether this is the page at the root of its collective, which is addressed by the collective itself rather than by a path within it.
    let isLandingPage: Bool

    /// `modification` is when the page was last changed, which is the order these are listed in.
    let modification: Date
}
