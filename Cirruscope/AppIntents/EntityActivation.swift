// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `EntityActivation` turns the identifier of a donated entity into the request that opens it.
///
/// It exists because two surfaces ask the same question and must not be allowed to answer it differently. An `Open…Intent` asks it when the Shortcuts app or Siri runs an action; `SpotlightSelection` asks it when a person taps a Spotlight result, which the system delivers as a plain activity rather than by running the intent. Both then have to look the entity up in the store, build the address that opens it, and decide what to do when either step fails — and when that logic lived inside the intents alone, the Spotlight side simply did not have it: every selection that was not a server app was dropped without a trace.
/// The collective page is what makes sharing this load-bearing rather than tidy. It is the one entity whose address may not be buildable and which therefore opens its *collective* instead, and a fallback that applied to the Shortcuts action but not to the Spotlight result would be the same feature behaving two ways.
///
/// Each address is logged where it is built, and deliberately **without** `privacy: .public`: a collective's path carries its name and a page's fallback path can carry its title, which is somebody's content rather than an identifier. It is in the clear for a build run from Xcode or a device carrying the logging profile, which is where anybody debugging a route actually is, and `<private>` in a sysdiagnose, which is where it would otherwise be somebody's private data. Not logging it at all was what turned a wrong address into a window that opened and showed the wrong thing with nothing in the record to say so.
///
/// Every function takes the store it reads from, defaulting to the process-wide one, so the production call sites are unchanged while a test can seed its own. That is the same arrangement `AccountStore`'s own closure seams use, and it is what lets these be covered at all: naming `AccountStore.shared` from a test would reach the developer's real store, whose recovery path deletes it.
@MainActor
enum EntityActivation {
    /// `Outcome` is what resolving one entity identifier came to.
    ///
    /// Three cases rather than an optional, because the two ways of failing are not the same thing to a caller. An entity the account no longer has is a bad *value*, which an intent answers by asking for another one; an entity that exists but cannot be addressed is a bad *address*, which nothing the user does would fix. Collapsing them would make an intent demand a new value for a note that is plainly still there.
    enum Outcome {
        /// `open` is a request the running app can serve.
        case open(EntityOpening.Request)

        /// `missing` is an entity the connected account no longer has.
        case missing

        /// `notAddressable` is an entity the account still has and which nothing can build an address for.
        case notAddressable
    }

    /// `logger` records how each identifier resolved, under the `EntityActivation` category.
    private static let logger = Logger(for: EntityActivation.self)

    /// `outcome(forServerAppID:in:)` resolves a Nextcloud app identifier to the request that opens it.
    ///
    /// A server app is opened by identity rather than by address, which is what lets macOS bring an already-open window forward instead of opening a second one showing the same app.
    static func outcome(forServerAppID id: String, in store: AccountStore = .shared) -> Outcome {
        guard let app = store.serverApp(forID: id) else {
            logger.error("The server is no longer offering a server app with id \"\(id, privacy: .public)\"")
            return .missing
        }

        logger.notice("Resolved server app \"\(app.id, privacy: .public)\"")
        return .open(.serverApp(app))
    }

    /// `outcome(forConversationToken:in:)` resolves a Talk conversation token to the request that opens it.
    static func outcome(forConversationToken token: String, in store: AccountStore = .shared) -> Outcome {
        guard let conversation = store.conversation(forToken: token) else {
            logger.error("The account no longer takes part in conversation \"\(token, privacy: .public)\"")
            return .missing
        }

        guard let serverAddress = store.serverAddress else {
            logger.error("No server is configured, so conversation \"\(token, privacy: .public)\" cannot be addressed")
            return .notAddressable
        }

        guard let target = ConversationWebRoute.url(forToken: conversation.id, on: serverAddress) else {
            logger.error("No address could be built for conversation \"\(conversation.id, privacy: .public)\"")
            return .notAddressable
        }

        logger.notice("Resolved conversation \"\(conversation.id, privacy: .public)\" to \(target.url.absoluteString)")
        return .open(.page(target))
    }

    /// `outcome(forNoteID:in:)` resolves a note identifier to the request that opens it.
    static func outcome(forNoteID id: Int, in store: AccountStore = .shared) -> Outcome {
        guard let note = store.note(forID: id) else {
            logger.error("The account no longer has note \(id, privacy: .public)")
            return .missing
        }

        guard let serverAddress = store.serverAddress else {
            logger.error("No server is configured, so note \(id, privacy: .public) cannot be addressed")
            return .notAddressable
        }

        guard let target = NoteWebRoute.url(forID: note.id, on: serverAddress) else {
            logger.error("No address could be built for note \(note.id, privacy: .public)")
            return .notAddressable
        }

        logger.notice("Resolved note \(note.id, privacy: .public) to \(target.url.absoluteString)")
        return .open(.page(target))
    }

    /// `outcome(forCollectiveID:in:)` resolves a collective identifier to the request that opens it.
    static func outcome(forCollectiveID id: Int, in store: AccountStore = .shared) -> Outcome {
        guard let collective = store.collective(forID: id) else {
            logger.error("The account is no longer a member of collective \(id, privacy: .public)")
            return .missing
        }

        guard let serverAddress = store.serverAddress else {
            logger.error("No server is configured, so collective \(id, privacy: .public) cannot be addressed")
            return .notAddressable
        }

        guard let target = CollectiveWebRoute.url(for: collective, on: serverAddress) else {
            logger.error("No address could be built for collective \(collective.id, privacy: .public)")
            return .notAddressable
        }

        logger.notice("Resolved collective \(collective.id, privacy: .public) to \(target.url.absoluteString)")
        return .open(.page(target))
    }

    /// `outcome(forCollectivePageID:in:)` resolves a page identifier to the request that opens it, falling back to the page's collective where no address for the page itself can be built.
    ///
    /// This is the one resolution here that falls back rather than refusing: a page whose address cannot be built at all opens the collective containing it, which is certainly the right neighbourhood, so a person who asked for a page and was shown its collective can see both what happened and where to go next. Opening nothing would look like the app had failed.
    static func outcome(forCollectivePageID id: Int, in store: AccountStore = .shared) -> Outcome {
        guard let page = store.collectivePage(forID: id) else {
            logger.error("The account no longer has collective page \(id, privacy: .public)")
            return .missing
        }

        guard let collective = store.collective(forID: page.collectiveID) else {
            logger.error("Collective \(page.collectiveID, privacy: .public) is gone, so page \(page.id, privacy: .public) cannot be addressed")
            return .missing
        }

        guard let serverAddress = store.serverAddress else {
            logger.error("No server is configured, so page \(page.id, privacy: .public) cannot be addressed")
            return .notAddressable
        }

        if let target = CollectivePageWebRoute.url(for: page, in: collective, on: serverAddress) {
            logger.notice("Resolved collective page \(page.id, privacy: .public) to \(target.url.absoluteString)")
            return .open(.page(target))
        }

        guard let fallback = CollectiveWebRoute.url(for: collective, on: serverAddress) else {
            logger.error("Neither page \(page.id, privacy: .public) nor its collective \(collective.id, privacy: .public) could be addressed")
            return .notAddressable
        }

        logger.notice("No address for page \(page.id, privacy: .public); resolved its collective \(collective.id, privacy: .public) instead, at \(fallback.url.absoluteString)")
        return .open(.page(fallback))
    }
}
