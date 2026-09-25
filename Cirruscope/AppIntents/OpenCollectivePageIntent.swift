// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenCollectivePageIntent` opens a chosen page within a collective, backing a Shortcuts action and activation of a `CollectivePageEntity` Spotlight result.
///
/// It is the one intent here whose resolution falls back rather than refusing: a page whose address cannot be built opens the **collective** containing it instead of opening nothing. The reasoning lives with the resolution, in `EntityActivation`, which is also what makes the fallback apply to a Spotlight tap and not only to this action.
struct OpenCollectivePageIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    static let title: LocalizedStringResource = "Open Nextcloud Collective Page"

    /// `description` explains the action in the Shortcuts app.
    static let description = IntentDescription("Open a page of a collective in Nextcloud Collectives.")

    /// `logger` records intent activity under the `OpenCollectivePageIntent` category.
    private static let logger = Logger(for: OpenCollectivePageIntent.self)

    /// `target` is the page to open, chosen from `CollectivePageEntity.defaultQuery`.
    @Parameter(title: "Page", requestValueDialog: "Which page?")
    var target: CollectivePageEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
    ///
    /// The resolution is shared with `SpotlightSelection` rather than written here, so that running this action and tapping the matching Spotlight result cannot come to different conclusions about the same entity.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open collective page \(target.id, privacy: .public)")

        switch EntityActivation.outcome(forCollectivePageID: target.id) {
            case let .open(request):
                EntityOpening.shared.open(request)
                return .result()

            case .missing:
                Self.logger.error("perform: the account no longer has this collective page; requesting a different value")
                throw $target.needsValueError()

            case .notAddressable:
                Self.logger.error("perform: nothing could be opened for this collective page")
                return .result()
        }
    }
}
