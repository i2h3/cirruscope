// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `CollectivePageEntity` is the App Intents projection of one page within a collective.
///
/// It is the only entity here whose subtitle is not a product name, and that is deliberate. A note's category is absent on most notes, so it would be a subtitle that comes and goes; a page always belongs to exactly one collective, and which collective a page is in is the thing a person needs to tell two pages called "Notes" apart. The product name moves into the keywords, where it still finds the page.
///
/// Its image is that emoji where it has one, drawn onto the same plate a server app's icon is drawn onto, and the Collectives app's own mark where it has none. The emoji is in the title as well, and carrying it in both places is the point rather than a duplication: a Spotlight row is read as a picture first and a line of text second, and pages within one collective are exactly the results a shared app mark would fail to tell apart.
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

    /// `collectiveName` is the name of the collective the page belongs to, which is what the result is subtitled with.
    ///
    /// Carried on the entity rather than looked up when the subtitle is read, because `displayRepresentation` is reached from outside the main actor and the store is not: resolving it once where the entity is built is both the only place the lookup is available and the only place it happens per entity rather than per read.
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

    /// `iconData` is the page's own emoji on the plated artwork, or the Collectives app's icon where it has none.
    ///
    /// Carried rather than looked up, for the reason `collectiveName` is: `displayRepresentation` is reached from outside the main actor and neither the store nor the icons are.
    var iconData: Data?

    /// `displayRepresentation` is how a single page appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    var displayRepresentation: DisplayRepresentation {
        guard let icon = iconData else {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(collectiveName)")
        }

        return DisplayRepresentation(title: "\(name)", subtitle: "\(collectiveName)", image: DisplayRepresentation.Image(data: icon))
    }

    /// `attributeSet` is the Spotlight metadata donated for this entity, keyworded with the server product, the owning app and the collective so a page is found by any of the three.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = collectiveName
        attributes.contentModificationDate = page.modification
        attributes.keywords = ["Nextcloud", "Collectives", collectiveName, page.title]
        attributes.thumbnailData = iconData
        return attributes
    }

    /// `init(_:inCollective:)` bridges a `CollectivePageTransferObject` snapshot into an entity, taking the name of the collective it belongs to alongside it.
    @MainActor
    init(_ page: CollectivePageTransferObject, inCollective collectiveName: String) {
        self.page = page
        self.collectiveName = collectiveName

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        iconData = ServerAppIconThumbnail.pngData(forEmoji: page.emoji, orAppID: CollectiveWebRoute.appID, serverAddress: serverAddress)
    }
}
