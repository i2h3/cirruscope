// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenConversationIntent` opens a chosen Nextcloud Talk conversation inside Cirruscope, backing a Shortcuts action and activation of a `ConversationEntity` Spotlight result.
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
    @Parameter(title: "Conversation", requestValueDialog: "Which conversation?")
    var target: ConversationEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
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
