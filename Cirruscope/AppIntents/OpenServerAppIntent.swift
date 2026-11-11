// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `OpenServerAppIntent` opens a chosen Nextcloud server app inside Cirruscope, backing the Shortcuts "Open Nextcloud App" action, the Siri phrases declared in `ServerAppShortcuts`, and activation of a `ServerAppEntity` Spotlight result.
struct OpenServerAppIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    static let title: LocalizedStringResource = "Open Nextcloud App"

    /// `description` explains the action in the Shortcuts app. It names no app because App Intents metadata is extracted statically at build time — a runtime value such as `Bundle.main.name` cannot be embedded — and the Shortcuts app already labels every action with the owning app's name and icon.
    static let description = IntentDescription("Open a Nextcloud server app.")

    /// `logger` records intent activity under the `OpenServerAppIntent` category.
    private static let logger = Logger(for: OpenServerAppIntent.self)

    /// `target` is the server app to open, chosen from `ServerAppEntity.defaultQuery`.
    @Parameter(title: "App", requestValueDialog: "Which app?")
    var target: ServerAppEntity

    /// `perform()` resolves `target` through `EntityActivation` and opens what it answers, or asks the user to pick another value when the account no longer has it.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open server app \"\(target.id, privacy: .public)\"")

        switch EntityActivation.outcome(forServerAppID: target.id) {
            case let .open(request):
                EntityOpening.shared.open(request)
                return .result()

            case .missing:
                Self.logger.error("perform: the account no longer has this server app; requesting a different value")
                throw $target.needsValueError()

            case .notAddressable:
                Self.logger.error("perform: nothing could be opened for this server app")
                return .result()
        }
    }
}
