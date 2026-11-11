// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenNoteIntent` opens a chosen note inside Cirruscope, backing a Shortcuts action and activation of a `NoteEntity` Spotlight result.
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
    @Parameter(title: "Note", requestValueDialog: "Which note?")
    var target: NoteEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
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
