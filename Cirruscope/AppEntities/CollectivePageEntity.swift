// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `CollectivePageEntity` is the App Intents projection of one page within a collective.
///
/// Its subtitle follows the same pattern as every other entity's rather than naming the collective the page is in, which it used to. That is a trade made knowingly: the collective's name is the better answer to "which of my two pages called Notes is this", and a column of mixed Spotlight results is the more common thing to be looking at, where one row reading "Nextcloud Handbook" among three reading "… in Nextcloud …" reads as a different kind of entry. Which collective a page belongs to is still carried — by the artwork, which is that collective's own emoji, and by the keywords, which find the page by its collective's name.
///
/// Its image is the **collective's** emoji, not the page's own, drawn onto the same plate a server app's icon is drawn onto, and the Collectives app's mark where the collective has none. That is the opposite of the obvious choice and is what a live instance settled: a page's own emoji is already the first thing in its title, so drawing it again says nothing a reader did not have, while the collective's emoji says which of several collectives the page came from — which the subtitle also says, and which is the thing a row of search results is actually being told apart by.
struct CollectivePageEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = CollectivePageEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    ///
    /// It names the collective rather than only Nextcloud, because a Nextcloud has plenty of things that are pages and this type is exactly one of them. "Collective page" is kept as a synonym: it is unambiguous enough to say out loud, unlike the bare "page" that is deliberately absent.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud collective page",
            numericFormat: "\(placeholder: .int) Nextcloud collective pages",
            synonyms: ["collective page"]
        )
    }

    /// `page` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var page: CollectivePageTransferObject

    /// `collectiveName` is the name of the collective the page belongs to, which is what a search for that collective finds the page by.
    ///
    /// Carried on the entity rather than looked up when the keywords are read, because `attributeSet` is reached from outside the main actor and the store is not: resolving it once where the entity is built is both the only place the lookup is available and the only place it happens per entity rather than per read.
    var collectiveName: String

    /// `id` is the page's server-assigned identifier, which is the identifier of its file and unique on the server.
    var id: Int {
        page.id
    }

    /// `name` is the page's title, with its emoji in front where it has one, declared as an entity property bound to Spotlight's `displayName`.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        guard let emoji = page.emoji, emoji.isEmpty == false else {
            return page.title
        }

        return "\(emoji) \(page.title)"
    }

    /// `iconData` is the owning collective's emoji on the plated artwork, or the Collectives app's icon where the collective has none.
    ///
    /// Carried rather than looked up, for the reason `collectiveName` is: `displayRepresentation` is reached from outside the main actor and neither the store nor the icons are.
    var iconData: Data?

    /// `displayRepresentation` is how a single page appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    var displayRepresentation: DisplayRepresentation {
        guard let icon = iconData else {
            return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle)
        }

        return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle, image: DisplayRepresentation.Image(data: icon))
    }

    /// `subtitle` is the one line of context a page carries besides its title, in the one place both surfaces that show it read from.
    ///
    /// Stated once because it reaches Spotlight twice by two different routes — as the display representation's subtitle and as the searchable item's `contentDescription` — and a result whose two descriptions disagreed would be this app contradicting itself.
    /// It follows the one pattern every entity's subtitle follows — *`<what it is>` in Nextcloud `<the app it lives in>`* — so that a column of mixed results reads as one list rather than four. The first half is the plain noun somebody would use for the thing, the second names the server app it belongs to, and neither is left to be inferred from the title: a Spotlight row is often the only context there is.
    private static let subtitle: LocalizedStringResource = "Page in Nextcloud Collectives"

    /// `attributeSet` is the Spotlight metadata donated for this entity, keyworded with the server product, the owning app and the collective so a page is found by any of the three.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = String(localized: Self.subtitle)
        attributes.contentModificationDate = page.modification
        attributes.keywords = ["Nextcloud", "Collectives", collectiveName, page.title]
        attributes.thumbnailData = iconData
        return attributes
    }

    /// `init(_:in:)` bridges a `CollectivePageTransferObject` snapshot into an entity, taking the collective it belongs to alongside it.
    ///
    /// The whole collective rather than only its name, because both of the things a page borrows from its collective are needed here and taking one of them would mean coming back for the other.
    @MainActor
    init(_ page: CollectivePageTransferObject, in collective: CollectiveTransferObject) {
        self.page = page
        collectiveName = collective.name

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        iconData = ServerAppIconThumbnail.pngData(forEmoji: collective.emoji, orAppID: CollectiveWebRoute.appID, serverAddress: serverAddress)
    }
}
