// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation

/// `CollectiveFixture` is the corpus of collectives and pages the collective suites run their cases over.
enum CollectiveFixture {
    /// `cookbook` is an ordinary collective, with a slug.
    static let cookbook = CollectiveTransferObject(id: 1, name: "Cookbook", slug: "cookbook", emoji: "📗")

    /// `handbook` is a collective on a server whose Collectives app predates slugs, so it has none.
    static let handbook = CollectiveTransferObject(id: 2, name: "Nextcloud Handbook", slug: nil, emoji: nil)

    /// `all` is every collective, in no meaningful order — the server returns them unsorted.
    static let all = [handbook, cookbook]

    /// `landingPage` is the page at the root of `cookbook`, which the collective's own address opens.
    static let landingPage = CollectivePageTransferObject(id: 10, collectiveID: 1, title: "Cookbook", slug: "cookbook", emoji: nil, fileName: "Readme.md", filePath: "", isLandingPage: true, modification: Date(timeIntervalSince1970: 1_700_000_100))

    /// `pancakes` is an ordinary page inside a folder of `cookbook`.
    static let pancakes = CollectivePageTransferObject(id: 11, collectiveID: 1, title: "Pancakes", slug: "pancakes", emoji: "🥞", fileName: "Pancakes.md", filePath: "Recipes", isLandingPage: false, modification: Date(timeIntervalSince1970: 1_700_000_300))

    /// `desserts` is a page with subpages, so the server stores it as the index file of a folder named after it.
    static let desserts = CollectivePageTransferObject(id: 12, collectiveID: 1, title: "Desserts", slug: "desserts", emoji: nil, fileName: "Readme.md", filePath: "Desserts", isLandingPage: false, modification: Date(timeIntervalSince1970: 1_700_000_200))

    /// `unsluggedPage` is a page on an instance whose Collectives app predates slugs, which is the only case still addressed by its path.
    static let unsluggedPage = CollectivePageTransferObject(id: 13, collectiveID: 1, title: "Waffles", slug: nil, emoji: nil, fileName: "Waffles.md", filePath: "Recipes", isLandingPage: false, modification: Date(timeIntervalSince1970: 1_700_000_400))

    /// `pages` is every page of `cookbook`, in no meaningful order.
    static let pages = [desserts, landingPage, pancakes]
}
