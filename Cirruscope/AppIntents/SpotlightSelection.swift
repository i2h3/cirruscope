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
/// **The entity's type is as load-bearing as its identifier**, and reading only the identifier is what made every donated item other than a server app open nothing at all. An identifier is unique within a type and not across them: `42` is a note and also a collective and also a page, so an app holding the string alone has no honest way to pick.
///
/// Spotlight delivers both, as one string of the form `<EntityTypeName>/<identifier>`, and **this reads that string itself rather than through `EntityIdentifier(activityIdentifier:)`**. That initializer looks like the right tool and is not: it is not a parser but a synchronous round trip into `linkd`'s App Intents index, which answers from whichever bundle Launch Services calls canonical for this bundle identifier. On a development machine that is not the app being run. Measured on a Mac with nine registrations of `de.i2h3.cirruscope`: Launch Services preferred an archive from two months earlier, whose metadata registered exactly one entity type, and `linkd` logged `Found existing canonical bundle with matching hash, skipping` rather than re-reading anything — so every selection but a server app's was refused with "is not a registered AppEntity identifier" while the running app's own metadata listed all five. Reproduced from scratch in a throwaway app to be sure it was the mechanism and not this project.
/// The type names are this app's own, compiled into it, and the five it knows are the five it donates; anything else is refused. So reading the string directly is not a shortcut around a check — it is the same check, made against the only registry that is certainly describing the app that is running.
///
/// `NSUserActivity.appEntityIdentifier` is deliberately not consulted. It cannot answer for a Spotlight continuation: assigning one leaves `userInfo` empty, because it is held out of band and does not survive the crossing, and an activity carrying only `CSSearchableItemActivityIdentifier` — which is exactly what Spotlight delivers — answers `nil`. Measured both ways, and corroborated by a device log showing this app fall straight through to the raw identifier. Reading it would also make the same failing call into `linkd`.
enum SpotlightSelection {
    /// `logger` records what a selection resolved to, under the `SpotlightSelection` category.
    private static let logger = Logger(for: SpotlightSelection.self)

    /// `Selection` is one Spotlight result read apart into the two things needed to act on it.
    ///
    /// A pair of strings rather than an `EntityIdentifier`, because that type cannot be built without asking the system which entity types this app has — a question the system answers about whichever copy of the app it happens to know, and on a development machine that is not this one.
    struct Selection {
        /// `typeName` is the entity type's Swift name, as this app's own metadata spells it.
        let typeName: String

        /// `identifier` is the entity's own identifier, still as text: what a numeric type means by it is read back where the type is known.
        let identifier: String
    }

    /// `selection(from:)` is the entity `userActivity` names, or `nil` when it is not a Spotlight selection or carries nothing recognizable.
    ///
    /// Answering `nil` for an activity of the wrong type rather than refusing to be called with one is deliberate: both platforms receive every kind of continuation through one entry point, so "is this even mine?" is part of the question being asked.
    /// The identifier is split on the *first* separator only. An entity identifier may contain one — a collective is addressed by its name where it has no slug — while a type name never does, so everything after the first separator belongs to the identifier.
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
    ///
    /// The identifier is re-resolved through the store rather than trusted, for the reason an intent re-resolves it too: a donated item outlives the list it was donated from, so the server may no longer offer what Spotlight is still showing.
    /// A `.missing` entity answers `nil` here rather than asking for another value the way an intent does. There is nothing to ask: the user picked a specific search result, and the honest response to one that no longer exists is to leave the app where it is and say so in the log.
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
    ///
    /// The names are the entity types' own, taken from the metatype rather than written out, so renaming a type cannot leave a string here pointing at nothing. Each identifier is read back to the entity's own `ID` on the way, which is where a page's `42` becomes an `Int` again — a selection carries it as text whatever the entity declares.
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
