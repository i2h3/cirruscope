// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import Foundation
import Testing

/// `ShortcutsNameTests` covers the names the Shortcuts app lists for this app, its action titles and entity type names: that each is translated in every localization the bundle ships, and that the type names are cased as names.
struct ShortcutsNameTests {
    /// `typeNames` are the names of the five entity types, as the declarations give them.
    static let typeNames: [LocalizedStringResource] = [
        ServerAppEntity.typeDisplayRepresentation.name,
        NoteEntity.typeDisplayRepresentation.name,
        ConversationEntity.typeDisplayRepresentation.name,
        CollectiveEntity.typeDisplayRepresentation.name,
        CollectivePageEntity.typeDisplayRepresentation.name,
    ]

    /// `actionTitles` are the titles of the five actions, as the intents declare them.
    static let actionTitles: [LocalizedStringResource] = [
        OpenServerAppIntent.title,
        OpenNoteIntent.title,
        OpenConversationIntent.title,
        OpenCollectiveIntent.title,
        OpenCollectivePageIntent.title,
    ]

    /// `missing` is what a lookup answers for a key its table lacks, chosen so that no translation can be it, because the key itself, the lookup's own default, already starts with a capital.
    static let missing = "\u{FFFD} missing \u{FFFD}"

    /// `localizations` are the languages the host bundle ships besides English, detected rather than listed so a language added later is covered without touching this suite.
    static let localizations = Bundle.main.localizations.filter { $0 != "en" && $0 != "Base" }

    @Test(arguments: actionTitles + typeNames, localizations)
    func `Every name the Shortcuts app lists is translated in every shipped localization`(name: LocalizedStringResource, localization: String) throws {
        let path = try #require(Bundle.main.path(forResource: localization, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let translated = bundle.localizedString(forKey: name.key, value: nil, table: name.table)

        #expect(translated != name.key, "\(name.key) is not translated into \(localization)")
    }

    @Test(arguments: typeNames)
    func `Every word of a type name starts with a capital in English`(name: LocalizedStringResource) {
        let words = name.key.split(separator: " ")

        #expect(words.isEmpty == false)
        #expect(words.allSatisfy { $0.first?.isUppercase == true }, "\(name.key) is not in title case")
    }

    @Test(arguments: typeNames, localizations)
    func `A type name starts with a capital in every shipped localization`(name: LocalizedStringResource, localization: String) throws {
        let path = try #require(Bundle.main.path(forResource: localization, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let translated = bundle.localizedString(forKey: name.key, value: Self.missing, table: name.table)

        #expect(translated != Self.missing, "\(name.key) has no entry in \(localization)")
        #expect(translated.first?.isUppercase == true, "\(name.key) reads \(translated) in \(localization)")
    }
}
