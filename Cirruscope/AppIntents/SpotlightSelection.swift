// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation
import os

/// `SpotlightSelection` reads which entity a user picked out of a Spotlight result, from the activity the system delivers.
enum SpotlightSelection {
    /// `logger` records what a selection resolved to, under the `SpotlightSelection` category.
    private static let logger = Logger(for: SpotlightSelection.self)

    /// `Selection` is one Spotlight result read apart into the two things needed to act on it.
    struct Selection {
        /// `typeName` is the entity type's Swift name, as this app's own metadata spells it.
        let typeName: String

        /// `identifier` is the entity's own identifier, still as text: what a numeric type means by it is read back where the type is known.
        let identifier: String
    }

    /// `selection(from:)` is the entity `userActivity` names, or `nil` when it is not a Spotlight selection or carries nothing recognizable.
    static func selection(from userActivity: NSUserActivity) -> Selection? {
        logger.notice("Continuing user activity of type \"\(userActivity.activityType, privacy: .public)\"")

        guard userActivity.activityType == CSSearchableItemActionType else {
            logger.debug("User activity is not a Spotlight selection; not handling it")
            return nil
        }

        guard let rawIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            logger.error("Spotlight selection carried no recognizable entity identifier; ignoring it")
            return nil
        }

        guard let separator = rawIdentifier.firstIndex(of: "/") else {
            logger.error("Spotlight selection's identifier \"\(rawIdentifier, privacy: .public)\" names no entity type; ignoring it rather than guessing which kind of entity it means")
            return nil
        }

        let typeName = String(rawIdentifier[rawIdentifier.startIndex ..< separator])
        let identifier = String(rawIdentifier[rawIdentifier.index(after: separator)...])

        guard identifier.isEmpty == false else {
            logger.error("Spotlight selection's identifier \"\(rawIdentifier, privacy: .public)\" names a type and nothing else; ignoring it")
            return nil
        }

        logger.notice("Spotlight selection names \(typeName, privacy: .public) \"\(identifier, privacy: .public)\"")
        return Selection(typeName: typeName, identifier: identifier)
    }

    /// `request(from:in:)` is what the running app should open for the Spotlight result `userActivity` names, or `nil` when there is nothing to open.
    @MainActor
    static func request(from userActivity: NSUserActivity, in store: AccountStore = .shared) -> EntityOpening.Request? {
        guard let selection = selection(from: userActivity) else {
            return nil
        }

        guard let outcome = outcome(for: selection, in: store) else {
            logger.error("Spotlight selection names an entity of type \(selection.typeName, privacy: .public), which this app does not donate; ignoring it")
            return nil
        }

        switch outcome {
            case let .open(request):
                return request

            case .missing, .notAddressable:
                logger.error("Nothing to open for Spotlight-selected \"\(selection.identifier, privacy: .public)\"")
                return nil
        }
    }

    /// `outcome(for:in:)` resolves a selection through `EntityActivation`, or answers `nil` for a type this app does not donate.
    @MainActor
    private static func outcome(for selection: Selection, in store: AccountStore) -> EntityActivation.Outcome? {
        let raw = selection.identifier

        switch selection.typeName {
            case String(describing: ServerAppEntity.self):
                return EntityActivation.outcome(forServerAppID: raw, in: store)

            case String(describing: ConversationEntity.self):
                return EntityActivation.outcome(forConversationToken: raw, in: store)

            case String(describing: NoteEntity.self):
                return numericIdentifier(raw).map { EntityActivation.outcome(forNoteID: $0, in: store) } ?? .missing

            case String(describing: CollectiveEntity.self):
                return numericIdentifier(raw).map { EntityActivation.outcome(forCollectiveID: $0, in: store) } ?? .missing

            case String(describing: CollectivePageEntity.self):
                return numericIdentifier(raw).map { EntityActivation.outcome(forCollectivePageID: $0, in: store) } ?? .missing

            default:
                return nil
        }
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
