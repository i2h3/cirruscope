// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `NoteEntity` is the App Intents projection of a note in the connected account's Nextcloud Notes app, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// **A note's text is not here, and could not be**: the value this projects has no field for one, and the refresh never downloads it. What a Spotlight result carries is a title and the category it is filed under, which is what finds a note; opening it is what shows it.
struct NoteEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = NoteEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud Note",
            numericFormat: "\(placeholder: .int) Nextcloud notes",
            synonyms: ["Nextcloud Notes note"]
        )
    }

    /// `note` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var note: NoteTransferObject

    /// `id` is the note's server-assigned identifier: what the route opening it requires, and what `OpenNoteIntent` resolves back through the store — so it is safe to donate to Spotlight and to persist inside a saved Shortcut.
    var id: Int {
        note.id
    }

    /// `name` is the note's title, declared as an entity property bound to Spotlight's `displayName` so Siri and Spotlight know which value carries the spoken name.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        note.title
    }

    /// `iconData` is the Nextcloud Notes app's own icon on the plated artwork, or `nil` if none has been rendered.
    var iconData: Data?

    /// `displayRepresentation` is how a single note appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    ///
    /// The subtitle names the owning server app rather than only the server product, as a conversation's does. A result reading "Groceries" with the subtitle "Nextcloud" would say where it came from but not what it is, and whether this opens a note or a file is the one thing a person needs before tapping it.
    /// The category is deliberately not in the subtitle, though it is the obvious candidate: most notes are filed under none, so it would be present on some rows and absent on others, and a subtitle that comes and goes reads as missing data rather than as a property not every note has. It is a keyword instead, where it is searchable and never seen to be absent.
    var displayRepresentation: DisplayRepresentation {
        guard let icon = iconData else {
            return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle)
        }

        return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle, image: DisplayRepresentation.Image(data: icon))
    }

    /// `subtitle` is the one line of context a note carries besides its title, in the one place both surfaces that show it read from.
    private static let subtitle: LocalizedStringResource = "Note in Nextcloud Notes"

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the title and subtitle, and adds keywords so the server product, the owning app and the note's own category all find it.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = String(localized: Self.subtitle)
        attributes.contentModificationDate = note.modification
        attributes.keywords = ["Nextcloud", "Notes", name] + (note.category.isEmpty ? [] : [note.category])
        attributes.thumbnailData = iconData
        return attributes
    }

    /// `init(_:)` bridges a `NoteTransferObject` snapshot into an entity, keeping the value type itself free of any App Intents dependency.
    @MainActor
    init(_ note: NoteTransferObject) {
        self.note = note

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        iconData = ServerAppIconThumbnail.pngData(forAppID: NoteWebRoute.appID, serverAddress: serverAddress)
    }
}
