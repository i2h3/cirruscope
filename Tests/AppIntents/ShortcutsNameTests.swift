// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import Foundation
import Testing

/// `ShortcutsNameTests` covers how the names the Shortcuts app shows for this app's entity types are cased, in English and in every localization the bundle ships.
///
/// The Shortcuts app titles the Find action it generates for each type with the type name, beside actions titled in title case, so a type name in sentence case reads as an app's name miswritten: "Nextcloud note" beside Nextcloud Notes (issue #136).
/// The names are read from the declarations themselves rather than restated, so a key that drifts from its catalog entry fails here too, and each localization is looked up the way the system resolves it, by the resource's own key and table in that language's `.lproj`.
/// Only the first letter is asserted for the translations, because French and Spanish type names are otherwise in sentence case, as Apple's own are; see `DECISIONS.md`.
struct ShortcutsNameTests {
    /// `typeNames` are the names of the five entity types, as the declarations give them.
    static let typeNames: [LocalizedStringResource] = [
        ServerAppEntity.typeDisplayRepresentation.name,
        NoteEntity.typeDisplayRepresentation.name,
        ConversationEntity.typeDisplayRepresentation.name,
        CollectiveEntity.typeDisplayRepresentation.name,
        CollectivePageEntity.typeDisplayRepresentation.name,
    ]

    /// `missing` is what a lookup answers for a key its table lacks, chosen so that no translation can be it, because the key itself, the lookup's own default, already starts with a capital.
    static let missing = "\u{FFFD} missing \u{FFFD}"

    /// `localizations` are the languages the host bundle ships besides English, detected rather than listed so a language added later is covered without touching this suite.
    static let localizations = Bundle.main.localizations.filter { $0 != "en" && $0 != "Base" }

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
