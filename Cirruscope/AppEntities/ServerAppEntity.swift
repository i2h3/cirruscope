// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreGraphics
import CoreSpotlight
import Foundation

/// `ServerAppEntity` is the App Intents projection of a Nextcloud server app, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
struct ServerAppEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = ServerAppEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud Server App",
            numericFormat: "\(placeholder: .int) Nextcloud server apps",
            synonyms: ["Nextcloud app", "server app"]
        )
    }

    /// `app` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var app: ServerAppTransferObject

    /// `iconData` is the app's own icon as PNG bytes, or `nil` if none has been downloaded for it.
    var iconData: Data?

    /// `id` is the Nextcloud app id (e.g. `"files"`): stable across relaunches and the store's rebuild-recovery, identical to `ServerAppTransferObject.id`, and the key `AppDelegate.openServerApp(_:)` matches on — so it is safe to donate to Spotlight and to persist inside a saved Shortcut.
    var id: String {
        app.id
    }

    /// `name` is the app's localized display name (e.g. `"Files"`), declared as an entity property bound to Spotlight's `displayName` so Siri and Spotlight know which value carries the spoken name.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        app.name
    }

    /// `displayRepresentation` is how a single entity appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    var displayRepresentation: DisplayRepresentation {
        guard let icon = iconData else {
            return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle)
        }

        return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle, image: DisplayRepresentation.Image(data: icon))
    }

    /// `subtitle` is the one line of context an app carries besides its name, in the one place both surfaces that show it read from.
    private static let subtitle: LocalizedStringResource = "Nextcloud"

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the `displayRepresentation`'s title and subtitle, adds `keywords` so a search such as "Nextcloud Notes" matches even though the title is only the bare app name, and carries the app's icon as the result's thumbnail.
    /// `thumbnailData` is the only one of the three thumbnail members that Spotlight actually draws. Its siblings `thumbnailURL` and `darkThumbnailURL` are left unset because setting them does nothing at all — measured, not assumed; `DECISIONS.md` records the probe.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = String(localized: Self.subtitle)
        attributes.keywords = ["Nextcloud", name]
        attributes.thumbnailData = iconData
        return attributes
    }

    /// `init(_:)` bridges a `ServerAppTransferObject` snapshot into an entity, keeping the DTO itself free of any App Intents dependency.
    @MainActor
    init(_ app: ServerAppTransferObject) {
        self.app = app

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        iconData = ServerAppIconThumbnail.pngData(forAppID: app.id, serverAddress: serverAddress)
    }
}
