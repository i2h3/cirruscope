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

    /// `perform()` resolves `target` to the current collective and opens it, or asks the user to pick another when the account is no longer a member of it.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open collective \(target.id, privacy: .public)")

        guard let collective = AccountStore.shared.collective(forID: target.id) else {
            Self.logger.error("perform: the account is no longer a member of collective \(target.id, privacy: .public); requesting a different value")
            throw $target.needsValueError()
        }

        guard let serverAddress = AccountStore.shared.serverAddress else {
            Self.logger.error("perform: no server is configured; nothing to open collective \(collective.id, privacy: .public) against")
            return .result()
        }

        guard let target = CollectiveWebRoute.url(forSlug: collective.slug, name: collective.name, on: serverAddress) else {
            Self.logger.error("perform: no address could be built for collective \(collective.id, privacy: .public); refusing to open anything")
            return .result()
        }

        Self.logger.notice("perform: opening collective \(collective.id, privacy: .public)")
        EntityOpening.shared.open(.page(target))
        return .result()
    }
}
