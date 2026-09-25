// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenNoteIntent` opens a chosen note inside Cirruscope, backing a Shortcuts action and activation of a `NoteEntity` Spotlight result.
///
/// It conforms to `OpenIntent` for the reason every one of these does: that conformance is the only thing recording the `com.apple.link.systemProtocol.OpenEntity` system protocol in the app's extracted metadata, and it requires the parameter be named exactly `target` — which is why there is one intent per entity type rather than one generic intent over a union.
///
/// `perform()` re-resolves the identifier through `AccountStore` rather than trusting the entity it was handed. A donated Spotlight item and a saved Shortcut both outlive the list they came from, and a note is a thing people delete.
struct OpenNoteIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    ///
    /// "Open Nextcloud Note" rather than naming the Notes app as well, matching the entity type this action takes: a Nextcloud has one thing called a note, so the app's name would be the product's name twice.
    static let title: LocalizedStringResource = "Open Nextcloud Note"

    /// `description` explains the action in the Shortcuts app. It names the owning server app, which is how someone browsing that list for what this app can do finds it at all.
    static let description = IntentDescription("Open a note in Nextcloud Notes.")

    /// `logger` records intent activity under the `OpenNoteIntent` category.
    private static let logger = Logger(for: OpenNoteIntent.self)

    /// `target` is the note to open, chosen from `NoteEntity.defaultQuery`.
    ///
    /// `OpenIntent` requires exactly this name. The title is bare rather than naming the server product, following the rule the App Intents strings keep: the action is already named for Nextcloud, so the parameter need not say it again.
    @Parameter(title: "Note", requestValueDialog: "Which note?")
    var target: NoteEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
    ///
    /// The resolution is shared with `SpotlightSelection` rather than written here, so that running this action and tapping the matching Spotlight result cannot come to different conclusions about the same entity.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open note \(target.id, privacy: .public)")

        switch EntityActivation.outcome(forNoteID: target.id) {
            case let .open(request):
                EntityOpening.shared.open(request)
                return .result()

            case .missing:
                Self.logger.error("perform: the account no longer has this note; requesting a different value")
                throw $target.needsValueError()

            case .notAddressable:
                Self.logger.error("perform: nothing could be opened for this note")
                return .result()
        }
    }
}
