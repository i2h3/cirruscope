// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ConversationEntity` is the App Intents projection of a Nextcloud Talk conversation, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// It follows `ServerAppEntity` in every load-bearing detail, and those details are load-bearing rather than stylistic: the `numericFormat` on the type representation and the `name` property bound to Spotlight's `displayName` are together what make an entity usable as a phrase parameter at all, established by diffing this app's extracted metadata against Apple's own sample. See `DECISIONS.md` for that investigation.
///
/// The image is the conversation's own picture where the server sent one this app can decode, and the Talk app's mark on the plated artwork otherwise. Both answers are wanted: a face is what tells two conversations apart at a glance, and the mark is what says "this is a conversation" for the many the server draws itself — as an SVG, which neither platform decodes. `ConversationAvatars` is where the fetching, the caching and the refusal live.
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

    /// `iconData` is the conversation's own picture, or the Talk app's icon on the plated artwork where there is none to draw.
    ///
    /// Carried rather than looked up, for the reason `ServerAppEntity` carries its own: these representations are read from outside the main actor and travel out of the process, while neither store is.
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
    ///
    /// Stated once because it reaches Spotlight twice by two different routes — as the display representation's subtitle and as the searchable item's `contentDescription` — and a result whose two descriptions disagreed would be this app contradicting itself.
    /// It names the *result* and not merely the app, which a live instance is what settled: a row reading "Camila Ayres" under "Nextcloud Talk" says where the thing came from but leaves what it is to be guessed at, and Talk holds calls and messages as well as conversations.
    /// It follows the one pattern every entity's subtitle follows — *`<what it is>` in Nextcloud `<the app it lives in>`* — so that a column of mixed results reads as one list rather than four. The first half is the plain noun somebody would use for the thing, the second names the server app it belongs to, and neither is left to be inferred from the title: a Spotlight row is often the only context there is.
    private static let subtitle: LocalizedStringResource = "Conversation in Nextcloud Talk"

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the title and subtitle, and adds keywords so a search for the product finds a conversation whose own name mentions neither.
    ///
    /// The thumbnail is whatever `iconData` resolved to, which is the conversation's own picture where one could be decoded.
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
