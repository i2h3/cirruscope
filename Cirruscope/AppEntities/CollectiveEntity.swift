// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `CollectiveEntity` is the App Intents projection of a collective the account is a member of, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// It follows the shape every entity here has, including the two details that carry weight — the `numericFormat` on the type representation and the `name` property bound to Spotlight's `displayName`, which together are what make an entity usable as a phrase parameter at all.
///
/// It donates no image. A collective is decorated with an emoji rather than an icon, and an emoji is already in the title where a person reads it; rendering one into a bitmap to hand Spotlight would be drawing a picture of text.
struct CollectiveEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = CollectiveEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    ///
    /// "Nextcloud collective" rather than naming the Collectives app as well: a Nextcloud has one thing called a collective, so the app's name would be the product's name twice. The synonym is there for someone who thinks of it by the app instead. A bare "collective" is deliberately not among them, for the reason a bare "app" is not among `ServerAppEntity`'s.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud collective",
            numericFormat: "\(placeholder: .int) Nextcloud collectives",
            synonyms: ["Nextcloud Collectives collective"]
        )
    }

    /// `collective` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var collective: CollectiveTransferObject

    /// `id` is the collective's server-assigned identifier, which `OpenCollectiveIntent` resolves back through the store.
    var id: Int {
        collective.id
    }

    /// `name` is the collective's name, with its emoji in front where it has one, declared as an entity property bound to Spotlight's `displayName`.
    ///
    /// The emoji is part of the name rather than a separate field because it is how the collective is recognized at a glance in Nextcloud's own interface, and a result that drops it looks like a different collective from the one the user knows.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        guard let emoji = collective.emoji, emoji.isEmpty == false else {
            return collective.name
        }

        return "\(emoji) \(collective.name)"
    }

    /// `displayRepresentation` is how a single collective appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Nextcloud Collectives")
    }

    /// `attributeSet` is the Spotlight metadata donated for this entity, adding keywords so the server product and the owning app both find a collective whose own name mentions neither.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["Nextcloud", "Collectives", collective.name]
        return attributes
    }

    /// `init(_:)` bridges a `CollectiveTransferObject` snapshot into an entity, keeping the value type itself free of any App Intents dependency.
    init(_ collective: CollectiveTransferObject) {
        self.collective = collective
    }
}
