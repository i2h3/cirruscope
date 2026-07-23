// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight

/// `ServerAppEntity` is the App Intents projection of a Nextcloud server app, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// It is a value-type snapshot bridged from the `ServerAppTransferObject` DTO that `AccountStore` vends, never a managed `@Model` object, so it can cross into the App Intents machinery freely. `ServerAppEntityQuery` produces and resolves these, `OpenServerAppIntent` opens the one the user picks, and — because it is an `IndexedEntity` — `ServerAppIndexer` donates the current set to the on-device Spotlight index.
struct ServerAppEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = ServerAppEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Nextcloud server app")
    }

    /// `id` is the Nextcloud app id (e.g. `"files"`): stable across relaunches and the store's rebuild-recovery, identical to `ServerAppTransferObject.id`, and the key `AppDelegate.openServerApp(_:)` matches on — so it is safe to donate to Spotlight and to persist inside a saved Shortcut.
    let id: String

    /// `name` is the app's localized display name (e.g. `"Files"`), used as the entity's title.
    let name: String

    /// `displayRepresentation` is how a single entity appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Nextcloud server app")
    }

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the `displayRepresentation`'s title and subtitle (which is why the Spotlight result shows the "Nextcloud server app" subtitle), and adds `keywords` so a search such as "Nextcloud Notes" matches even though the title is only the bare app name.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["Nextcloud", name]
        return attributes
    }

    /// `init(_:)` bridges a `ServerAppTransferObject` snapshot into an entity, keeping the DTO itself free of any App Intents dependency.
    init(_ app: ServerAppTransferObject) {
        id = app.id
        name = app.name
    }
}
