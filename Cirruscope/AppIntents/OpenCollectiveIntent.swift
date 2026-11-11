// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenCollectiveIntent` opens a chosen collective inside Cirruscope, backing a Shortcuts action and activation of a `CollectiveEntity` Spotlight result.
struct OpenCollectiveIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    static let title: LocalizedStringResource = "Open Nextcloud Collective"

    /// `description` explains the action in the Shortcuts app. It names the owning server app, which is how someone browsing that list finds it.
    static let description = IntentDescription("Open a collective in Nextcloud Collectives.")

    /// `logger` records intent activity under the `OpenCollectiveIntent` category.
    private static let logger = Logger(for: OpenCollectiveIntent.self)

    /// `target` is the collective to open, chosen from `CollectiveEntity.defaultQuery`.
    @Parameter(title: "Collective", requestValueDialog: "Which collective?")
    var target: CollectiveEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open collective \(target.id, privacy: .public)")

        switch EntityActivation.outcome(forCollectiveID: target.id) {
            case let .open(request):
                EntityOpening.shared.open(request)
                return .result()

            case .missing:
                Self.logger.error("perform: the account no longer has this collective; requesting a different value")
                throw $target.needsValueError()

            case .notAddressable:
                Self.logger.error("perform: nothing could be opened for this collective")
                return .result()
        }
    }
}
