// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation
import os

/// `SpotlightSelection` reads which entity a user picked out of a Spotlight result, from the activity the system delivers.
///
/// It exists because App Intents does not run the matching `Open…Intent` on the app's behalf when a donated item is selected — the system foregrounds the app and hands it a `CSSearchableItemActionType` activity instead, and recovering the entity from that is the app's job. Both platforms have to do it and neither can do it the other's way: AppKit delivers the activity through `NSApplicationDelegate`, SwiftUI through `onContinueUserActivity`. What is identical is everything between the activity arriving and the app knowing what to open, which is all that lives here.
///
/// **The entity's type is as load-bearing as its identifier**, and reading only the identifier is what made every donated item other than a server app open nothing at all. An identifier is unique within a type and not across them: `42` is a note and also a collective and also a page, so an app holding the string alone has no honest way to pick. `EntityIdentifier` carries the type alongside the identifier, and that is what this reads.
enum SpotlightSelection {
    /// `logger` records what a selection resolved to, under the `SpotlightSelection` category.
    private static let logger = Logger(for: SpotlightSelection.self)

    /// `identifier(from:)` is the typed identifier of the entity `userActivity` names, or `nil` when it is not a Spotlight selection or carries nothing recognizable.
    ///
    /// Answering `nil` for an activity of the wrong type rather than refusing to be called with one is deliberate: both platforms receive every kind of continuation through one entry point, so "is this even mine?" is part of the question being asked.
    /// An identifier is read from App Intents' own annotation where there is one and parsed out of the raw Spotlight identifier otherwise. Both are tried because the annotation is the documented path and the fallback is what answers for an item donated by an earlier launch. What is *not* done is falling back further, to the raw string with no type attached: that string cannot be resolved without guessing which kind of thing it names, and a guess here would open a note when a page was asked for. Such a selection is refused instead, which at least says so in the log.
    static func identifier(from userActivity: NSUserActivity) -> EntityIdentifier? {
        logger.notice("Continuing user activity of type \"\(userActivity.activityType, privacy: .public)\"")

        guard userActivity.activityType == CSSearchableItemActionType else {
            logger.debug("User activity is not a Spotlight selection; not handling it")
            return nil
        }

        if let identifier = userActivity.appEntityIdentifier {
            logger.notice("Spotlight selection carries the App Intents identifier \"\(identifier.identifier, privacy: .public)\" of type \(String(describing: identifier.entityType), privacy: .public)")
            return identifier
        }

        guard let rawIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            logger.error("Spotlight selection carried no recognizable entity identifier; ignoring it")
            return nil
        }

        guard let identifier = EntityIdentifier(activityIdentifier: rawIdentifier) else {
            logger.error("Spotlight selection's raw identifier \"\(rawIdentifier, privacy: .public)\" could not be read as a typed entity identifier; ignoring it rather than guessing which kind of entity it names")
            return nil
        }

        logger.notice("Spotlight selection's raw identifier resolved to \"\(identifier.identifier, privacy: .public)\" of type \(String(describing: identifier.entityType), privacy: .public)")
        return identifier
    }

    /// `request(from:in:)` is what the running app should open for the Spotlight result `userActivity` names, or `nil` when there is nothing to open.
    ///
    /// The identifier is re-resolved through the store rather than trusted, for the reason an intent re-resolves it too: a donated item outlives the list it was donated from, so the server may no longer offer what Spotlight is still showing.
    /// A `.missing` entity answers `nil` here rather than asking for another value the way an intent does. There is nothing to ask: the user picked a specific search result, and the honest response to one that no longer exists is to leave the app where it is and say so in the log.
    @MainActor
    static func request(from userActivity: NSUserActivity, in store: AccountStore = .shared) -> EntityOpening.Request? {
        guard let identifier = identifier(from: userActivity) else {
            return nil
        }

        guard let outcome = outcome(for: identifier, in: store) else {
            logger.error("Spotlight selection names an entity of type \(String(describing: identifier.entityType), privacy: .public), which this app does not donate; ignoring it")
            return nil
        }

        switch outcome {
            case let .open(request):
                return request

            case .missing, .notAddressable:
                logger.error("Nothing to open for Spotlight-selected \"\(identifier.identifier, privacy: .public)\"")
                return nil
        }
    }

    /// `outcome(for:in:)` resolves a typed identifier through `EntityActivation`, or answers `nil` for a type this app does not donate.
    ///
    /// The types are compared rather than switched over, there being no pattern that matches a metatype. Each identifier is parsed to the entity's own `ID` on the way, which is where a page's `42` becomes an `Int` again — the activity carries it as text whatever the entity declares.
    @MainActor
    private static func outcome(for identifier: EntityIdentifier, in store: AccountStore) -> EntityActivation.Outcome? {
        let entityType = identifier.entityType
        let raw = identifier.identifier

        if entityType == ServerAppEntity.self {
            return EntityActivation.outcome(forServerAppID: raw, in: store)
        }

        if entityType == ConversationEntity.self {
            return EntityActivation.outcome(forConversationToken: raw, in: store)
        }

        if entityType == NoteEntity.self {
            return numericIdentifier(raw).map { EntityActivation.outcome(forNoteID: $0, in: store) } ?? .missing
        }

        if entityType == CollectiveEntity.self {
            return numericIdentifier(raw).map { EntityActivation.outcome(forCollectiveID: $0, in: store) } ?? .missing
        }

        if entityType == CollectivePageEntity.self {
            return numericIdentifier(raw).map { EntityActivation.outcome(forCollectivePageID: $0, in: store) } ?? .missing
        }

        return nil
    }

    /// `numericIdentifier(_:)` reads the identifier of an entity whose `ID` is a number, or `nil` when the activity carried something else.
    private static func numericIdentifier(_ raw: String) -> Int? {
        guard let identifier = Int(raw) else {
            logger.error("Spotlight selection's identifier \"\(raw, privacy: .public)\" is not a number, though its entity type is identified by one")
            return nil
        }

        return identifier
    }
}
