// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenConversationIntent` opens a chosen Nextcloud Talk conversation inside Cirruscope, backing a Shortcuts action and activation of a `ConversationEntity` Spotlight result.
///
/// It conforms to `OpenIntent` for the same reason `OpenServerAppIntent` does, and it is not optional: that conformance is the only thing that records the `com.apple.link.systemProtocol.OpenEntity` system protocol in the app's extracted metadata, and without that entry the system does not recognise a parameter as a phrase token at all. `OpenIntent` requires the parameter be named exactly `target`, which is why there is one intent per entity type rather than one generic intent over a union of them.
///
/// `perform()` re-resolves the token through `AccountStore` rather than trusting the entity it was handed. A donated Spotlight item and a saved Shortcut both outlive the list they came from, so the conversation may be one the account has since left — and the alternative to re-resolving is opening an address built from a stale name for a conversation that is no longer there.
struct OpenConversationIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    ///
    /// It names the server app rather than only the server product, matching the entity type this action takes: someone searching the Shortcuts action list is scanning names, and "Open Nextcloud Conversation" would leave them to work out which of a Nextcloud's several ways of talking to people this opens.
    static let title: LocalizedStringResource = "Open Nextcloud Talk Conversation"

    /// `description` explains the action in the Shortcuts app. It names the server product rather than this app, because the Shortcuts app already labels every action with the owning app's name and icon, while nothing else there says whose conversations these are.
    static let description = IntentDescription("Open a conversation in Nextcloud Talk.")

    /// `logger` records intent activity under the `OpenConversationIntent` category.
    private static let logger = Logger(for: OpenConversationIntent.self)

    /// `target` is the conversation to open, chosen from `ConversationEntity.defaultQuery`.
    ///
    /// `OpenIntent` requires exactly this name. The title is bare rather than naming the server product, following the rule the App Intents strings already keep: the surrounding context carries it, and a parameter reading "Nextcloud conversation" beside an action already named for Nextcloud says it twice.
    @Parameter(title: "Conversation", requestValueDialog: "Which conversation?")
    var target: ConversationEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
    ///
    /// The resolution is shared with `SpotlightSelection` rather than written here, so that running this action and tapping the matching Spotlight result cannot come to different conclusions about the same entity.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open conversation \"\(target.id, privacy: .public)\"")

        switch EntityActivation.outcome(forConversationToken: target.id) {
            case let .open(request):
                EntityOpening.shared.open(request)
                return .result()

            case .missing:
                Self.logger.error("perform: the account no longer has this conversation; requesting a different value")
                throw $target.needsValueError()

            case .notAddressable:
                Self.logger.error("perform: nothing could be opened for this conversation")
                return .result()
        }
    }
}
