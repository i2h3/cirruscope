// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import AppKit
import os

/// `OpenServerAppIntent` opens a chosen Nextcloud server app inside Cirruscope, backing the Shortcuts "Open Nextcloud App" action, the Siri phrases declared in `CirruscopeAppShortcuts`, and activation of a `ServerAppEntity` Spotlight result.
///
/// As an `OpenIntent` it foregrounds the app when run. `perform()` re-resolves the selected `ServerAppEntity` to a fresh `ServerAppTransferObject` through `AccountStore` — rather than trusting a possibly-stale donated entity — and hands it to `AppDelegate.openServerApp(_:)`, reusing the same focus-an-existing-window-or-open-a-new-one logic as the View and Dock menus. Every branch of `perform()` logs at `.notice` (misses at `.error`) with the app id in the clear, so a log capture shows exactly which app was requested and whether it opened. The logger is `static` because App Intents instantiates the intent as a plain value with a synthesized `init()`.
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

    /// `perform()` resolves `target` to the current app snapshot and opens it, or asks the user to pick another app when the server no longer offers it.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open server app with id \"\(target.id, privacy: .public)\"")

        guard let app = AccountStore.shared.serverApp(forID: target.id) else {
            Self.logger.error("perform: no server app with id \"\(target.id, privacy: .public)\" is currently offered by the server; requesting a different value")
            throw $target.needsValueError()
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            Self.logger.error("perform: no AppDelegate available; cannot open \"\(app.id, privacy: .public)\"")
            return .result()
        }

        Self.logger.notice("perform: resolved \"\(app.name, privacy: .public)\" (\(app.id, privacy: .public)); handing to AppDelegate.openServerApp")
        appDelegate.openServerApp(app)
        Self.logger.notice("perform: finished opening \"\(app.id, privacy: .public)\"")
        return .result()
    }
}
