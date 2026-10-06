// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `PageLanguageTests` covers `PageLanguage.adopt(_:)`, the decision whether a page that has just finished loading means the account's language changed and the app list has to be fetched again.
///
/// Both halves of a wrong answer cost something the user notices: a change missed leaves every menu naming the apps in the previous language until the next launch (issue #138), and a change invented where there is none refetches the list and every icon on an ordinary page load.
/// So the cases pin that the first language is a baseline, that a repeat is not a change, that nothing reported changes nothing, and that a regional variant counts as a language of its own, as Nextcloud translates it as one.
struct PageLanguageTests {
    @Test
    func `The first language reported is a baseline rather than a change`() {
        var language = PageLanguage()

        #expect(language.adopt("de") == false)
        #expect(language.current == "de")
    }

    @Test
    func `The same language again is not a change`() {
        var language = PageLanguage()
        _ = language.adopt("de")

        #expect(language.adopt("de") == false)
        #expect(language.current == "de")
    }

    @Test
    func `Another language is a change and becomes the current one`() {
        var language = PageLanguage()
        _ = language.adopt("de")

        #expect(language.adopt("fr") == true)
        #expect(language.current == "fr")
    }

    @Test
    func `Changing back is a change again`() {
        var language = PageLanguage()
        _ = language.adopt("de")
        _ = language.adopt("fr")

        #expect(language.adopt("de") == true)
        #expect(language.current == "de")
    }

    @Test(arguments: [nil, ""] as [String?])
    func `Nothing reported records nothing, before a baseline and after one`(reported: String?) {
        var language = PageLanguage()

        #expect(language.adopt(reported) == false)
        #expect(language.current == nil)

        _ = language.adopt("de")

        #expect(language.adopt(reported) == false)
        #expect(language.current == "de")
    }

    @Test
    func `A regional variant counts as a language of its own`() {
        var language = PageLanguage()
        _ = language.adopt("de")

        #expect(language.adopt("de-DE") == true)
    }
}
