// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ConversationEntity` is the App Intents projection of a Nextcloud Talk conversation, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// Its identifier is the conversation's token, which is both what Talk addresses a conversation by and what the route opening one requires. It is stable for the life of the conversation, which is what lets a donated Spotlight item and a saved Shortcut keep meaning the same thing.
struct ConversationEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = ConversationEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud Talk Conversation",
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

    /// `iconData` is the conversation's own picture, or the Talk app's icon on the plated artwork where there is none to draw.
    var iconData: Data?

    /// `displayRepresentation` is how a single conversation appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    ///
    /// The subtitle names the owning server app rather than only the server product. A result reading "Alice Adams" with the subtitle "Nextcloud" would say where it came from but not what it is, and the one thing a person needs to know before tapping it is that this opens a conversation rather than a file or a contact.
    var displayRepresentation: DisplayRepresentation {
        guard let icon = iconData else {
            return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle)
        }

        return DisplayRepresentation(title: "\(name)", subtitle: Self.subtitle, image: DisplayRepresentation.Image(data: icon))
    }

    /// `subtitle` is the one line of context a conversation carries besides its name, in the one place both surfaces that show it read from.
    private static let subtitle: LocalizedStringResource = "Conversation in Nextcloud Talk"

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the title and subtitle, and adds keywords so a search for the product finds a conversation whose own name mentions neither.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = String(localized: Self.subtitle)
        attributes.contentModificationDate = conversation.lastActivity
        attributes.keywords = ["Nextcloud", "Talk", name]
        attributes.thumbnailData = iconData
        return attributes
    }

    /// `init(_:)` bridges a `ConversationTransferObject` snapshot into an entity, keeping the value type itself free of any App Intents dependency.
    @MainActor
    init(_ conversation: ConversationTransferObject) {
        self.conversation = conversation

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        iconData = Self.artwork(for: conversation, on: serverAddress)
    }

    /// `artwork(for:on:)` is the conversation's own picture made donatable, or the Talk mark when there is none.
    ///
    /// The fallback covers three cases at once and deliberately does not tell them apart, because the answer is the same for all three: nothing has been fetched yet, the server drew something this cannot decode, or there is no account to name the cache key with.
    @MainActor
    private static func artwork(for conversation: ConversationTransferObject, on serverAddress: URL) -> Data? {
        guard let credentials = Keychain.credentials(for: serverAddress) else {
            return ServerAppIconThumbnail.pngData(forAppID: ConversationWebRoute.appID, serverAddress: serverAddress)
        }

        guard let picture = ConversationAvatars.shared.image(forToken: conversation.id, avatarVersion: conversation.avatarVersion, accountName: credentials.user, serverAddress: serverAddress) else {
            return ServerAppIconThumbnail.pngData(forAppID: ConversationWebRoute.appID, serverAddress: serverAddress)
        }

        guard let composed = ServerAppIconThumbnail.pngData(compositing: picture) else {
            return ServerAppIconThumbnail.pngData(forAppID: ConversationWebRoute.appID, serverAddress: serverAddress)
        }

        return composed
    }
}
