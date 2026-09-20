// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ConversationEntity` is the App Intents projection of a Nextcloud Talk conversation, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// It follows `ServerAppEntity` in every load-bearing detail, and those details are load-bearing rather than stylistic: the `numericFormat` on the type representation and the `name` property bound to Spotlight's `displayName` are together what make an entity usable as a phrase parameter at all, established by diffing this app's extracted metadata against Apple's own sample. See `DECISIONS.md` for that investigation.
///
/// Where it departs from `ServerAppEntity` is the image, and it departs deliberately: a server app has an icon the server publishes, while a conversation has a picture the server renders per conversation and per appearance, which would be a request each and a cache keyed four ways. None is donated, so Spotlight and the Shortcuts app draw their own generic mark — which `ServerAppEntity`'s own documentation already argues is a better answer than an app inventing a second placeholder.
///
/// Its identifier is the conversation's token, which is both what Talk addresses a conversation by and what the route opening one requires. It is stable for the life of the conversation, which is what lets a donated Spotlight item and a saved Shortcut keep meaning the same thing.
struct ConversationEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = ConversationEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    ///
    /// It names the server app and not only the server product, because that is the whole of what the surface has to go on: the Shortcuts app shows this where a parameter's type goes, and "Nextcloud conversation" would leave a reader to guess which of a Nextcloud's several ways of talking to people is meant. The app is called Talk and the thing is called a conversation, so the type is what the user would call it.
    /// The numeric form says the same thing, and has to: it is the plural of this name rather than a phrase of its own, and a type shown as "Nextcloud Talk conversation" that counts itself as "3 Nextcloud conversations" is a surface disagreeing with itself.
    /// The synonyms widen what a spoken phrase may call the type. "Nextcloud conversation" is among them precisely because it is what the type used to be called and remains a reasonable thing to say; a bare "conversation" is deliberately not, for the same reason a bare "app" is not among `ServerAppEntity`'s — too generic to match on without dragging in utterances that have nothing to do with this app.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud Talk conversation",
            numericFormat: "\(placeholder: .int) Nextcloud Talk conversations",
            synonyms: ["Talk conversation", "Nextcloud conversation"]
        )
    }

    /// `conversation` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var conversation: ConversationTransferObject

    /// `id` is the conversation's Talk token: stable for the life of the conversation, identical to `ConversationTransferObject.id`, and the value `OpenConversationIntent` resolves back through the store — so it is safe to donate to Spotlight and to persist inside a saved Shortcut.
    var id: String {
        conversation.id
    }

    /// `name` is the conversation's display name, declared as an entity property bound to Spotlight's `displayName` so Siri and Spotlight know which value carries the spoken name.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        conversation.name
    }

    /// `displayRepresentation` is how a single conversation appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    ///
    /// The subtitle names the owning server app rather than only the server product. A result reading "Alice Adams" with the subtitle "Nextcloud" would say where it came from but not what it is, and the one thing a person needs to know before tapping it is that this opens a conversation rather than a file or a contact.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Nextcloud Talk")
    }

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the title and subtitle, and adds keywords so a search for the product finds a conversation whose own name mentions neither.
    ///
    /// No thumbnail is set. `ServerAppEntity` donates one because the server publishes an icon per app that is cheap to have already; a conversation's picture is rendered per conversation and per appearance and would have to be fetched, decoded — often from SVG — and cached before an index pass could carry it.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["Nextcloud", "Talk", name]
        return attributes
    }

    /// `init(_:)` bridges a `ConversationTransferObject` snapshot into an entity, keeping the value type itself free of any App Intents dependency.
    init(_ conversation: ConversationTransferObject) {
        self.conversation = conversation
    }
}
