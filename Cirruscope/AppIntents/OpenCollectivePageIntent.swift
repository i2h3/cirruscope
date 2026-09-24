// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenCollectivePageIntent` opens a chosen page within a collective, backing a Shortcuts action and activation of a `CollectivePageEntity` Spotlight result.
///
/// It is the one intent here that falls back rather than refusing. Every other address this app builds was read out of the owning app's own routing; a page's was derived, and is the one route in the codebase not verified against a live server — see `CollectivePageWebRoute`. So when a page's address cannot be built, this opens the **collective** containing it instead of opening nothing: that address is the better-supported of the two, it is certainly the right neighbourhood, and a user who asked for a page and was shown its collective can see both what happened and where to go next. Opening nothing would look like the app had failed; opening something arbitrary would be worse still.
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

    /// `perform()` resolves `target` to the current page and opens it, falling back to its collective where no address for the page itself can be built.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open collective page \(target.id, privacy: .public)")

        guard let page = AccountStore.shared.collectivePage(forID: target.id) else {
            Self.logger.error("perform: the account no longer has collective page \(target.id, privacy: .public); requesting a different value")
            throw $target.needsValueError()
        }

        guard let collective = AccountStore.shared.collective(forID: page.collectiveID) else {
            Self.logger.error("perform: collective \(page.collectiveID, privacy: .public) is gone, so page \(page.id, privacy: .public) cannot be addressed; requesting a different value")
            throw $target.needsValueError()
        }

        guard let serverAddress = AccountStore.shared.serverAddress else {
            Self.logger.error("perform: no server is configured; nothing to open page \(page.id, privacy: .public) against")
            return .result()
        }

        if let target = CollectivePageWebRoute.url(collectiveSlug: collective.slug, collectiveName: collective.name, page: page, on: serverAddress) {
            Self.logger.notice("perform: opening collective page \(page.id, privacy: .public)")
            EntityOpening.shared.open(.page(target))
            return .result()
        }

        guard let fallback = CollectiveWebRoute.url(forSlug: collective.slug, name: collective.name, on: serverAddress) else {
            Self.logger.error("perform: neither page \(page.id, privacy: .public) nor its collective could be addressed; refusing to open anything")
            return .result()
        }

        Self.logger.notice("perform: no address for page \(page.id, privacy: .public); opening collective \(collective.id, privacy: .public) instead")
        EntityOpening.shared.open(.page(fallback))
        return .result()
    }
}
