// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation
import os

/// `SpotlightSelection` reads which entity a user picked out of a Spotlight result, from the activity the system delivers.
///
/// It exists because App Intents does not run `OpenServerAppIntent` on the app's behalf when a donated item is selected — the system foregrounds the app and hands it a `CSSearchableItemActionType` activity instead, and recovering the entity from that is the app's job. Both platforms have to do it and neither can do it the other's way: AppKit delivers the activity through `NSApplicationDelegate`, SwiftUI through `onContinueUserActivity`. What is identical is everything between the activity arriving and the app knowing which entity it names, which is all that lives here.
///
/// The identifier is read from App Intents' own annotation where there is one and parsed out of the raw Spotlight identifier otherwise. Both are tried because the annotation is the documented path and the fallback is what actually answers for an item donated by an earlier launch.
enum SpotlightSelection {
    /// `logger` records what a selection resolved to, under the `SpotlightSelection` category.
    private static let logger = Logger(for: SpotlightSelection.self)

    /// `entityIdentifier(from:)` is the identifier of the entity `userActivity` names, or `nil` when it is not a Spotlight selection or carries nothing recognizable.
    ///
    /// Answering `nil` for an activity of the wrong type rather than refusing to be called with one is deliberate: both platforms receive every kind of continuation through one entry point, so "is this even mine?" is part of the question being asked.
    static func entityIdentifier(from userActivity: NSUserActivity) -> String? {
        logger.notice("Continuing user activity of type \"\(userActivity.activityType, privacy: .public)\"")

        guard userActivity.activityType == CSSearchableItemActionType else {
            logger.debug("User activity is not a Spotlight selection; not handling it")
            return nil
        }

        if let identifier = userActivity.appEntityIdentifier {
            logger.notice("Spotlight selection carries the App Intents identifier \"\(identifier.identifier, privacy: .public)\"")
            return identifier.identifier
        }

        guard let rawIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            logger.error("Spotlight selection carried no recognizable entity identifier; ignoring it")
            return nil
        }

        guard let identifier = EntityIdentifier(activityIdentifier: rawIdentifier)?.identifier else {
            logger.error("Spotlight selection's raw identifier could not be read as an entity identifier; ignoring it")
            return nil
        }

        logger.notice("Spotlight selection's raw identifier resolved to \"\(identifier, privacy: .public)\"")
        return identifier
    }

    /// `serverApp(from:)` is the server app `userActivity` names and the account still offers, or `nil`.
    ///
    /// The identifier is re-resolved through `AccountStore` rather than trusted, for the reason `OpenServerAppIntent.perform()` re-resolves it too: a donated item outlives the app list it was donated from, so the server may no longer offer what Spotlight is still showing.
    @MainActor
    static func serverApp(from userActivity: NSUserActivity) -> ServerAppTransferObject? {
        guard let appID = entityIdentifier(from: userActivity) else {
            return nil
        }

        guard let app = AccountStore.shared.serverApp(forID: appID) else {
            logger.error("Spotlight-selected server app \"\(appID, privacy: .public)\" is no longer offered by the server; ignoring it")
            return nil
        }

        logger.notice("Spotlight selected server app \"\(app.name, privacy: .public)\" (\(app.id, privacy: .public))")
        return app
    }
}
