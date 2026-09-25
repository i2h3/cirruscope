// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenCollectiveIntent` opens a chosen collective inside Cirruscope, backing a Shortcuts action and activation of a `CollectiveEntity` Spotlight result.
///
/// It conforms to `OpenIntent` for the reason every one of these does: that conformance is the only thing recording the `com.apple.link.systemProtocol.OpenEntity` system protocol in the app's extracted metadata, and it requires the parameter be named exactly `target`.
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
    ///
    /// The resolution is shared with `SpotlightSelection` rather than written here, so that running this action and tapping the matching Spotlight result cannot come to different conclusions about the same entity.
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
