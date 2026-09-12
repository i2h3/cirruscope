// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ActivityRowTests` covers the rules `ActivityRow` applies when it reduces a Nextcloud activity to the line a widget draws.
///
/// Neither test target links Rainmaker, so an `ActivityItem` cannot be built here and `init(_:)` cannot be exercised directly — `UnreadNotifications.badgeUpdate(forFetchedCount:)` is factored out for the same reason and says so. What that initializer actually decides, though, is in the three functions below plus `ActivityVerb`, and those take and answer strings. The cases are the shapes Nextcloud's own recorded responses contain, not invented ones: the rich `file` parameter spells a path without a leading separator, while `objectName` spells the same file with one, and both reach these functions depending on which the server sent.
///
struct ActivityRowTests {
    // MARK: - Directory

    ///
    /// A file inside folders reports the folders, whichever way the server spelled the path.
    ///
    @Test(arguments: [
        "Documents/Planning/Q3 Roadmap.md",
        "/Documents/Planning/Q3 Roadmap.md",
    ])
    func `A nested path reports its folders`(path: String) {
        #expect(ActivityRow.directory(ofPath: path) == "Documents/Planning")
    }

    ///
    /// A file at the account's root has no folder to name, and must not report a separator or the filename itself.
    ///
    @Test(arguments: ["Readme.md", "/Readme.md", "", "/"])
    func `A path at the root reports no folder`(path: String) {
        #expect(ActivityRow.directory(ofPath: path).isEmpty)
    }

    ///
    /// A trailing separator is what a folder's own path looks like, and must not produce an empty last component that swallows the real parent.
    ///
    @Test
    func `A trailing separator does not shift the folder`() {
        #expect(ActivityRow.directory(ofPath: "Design/Archive/") == "Design")
    }

    // MARK: - File Name

    ///
    /// The filename is the last component, with either spelling of the path.
    ///
    @Test(arguments: [
        "Documents/Planning/Q3 Roadmap.md",
        "/Documents/Planning/Q3 Roadmap.md",
    ])
    func `A path reports its last component as the file name`(path: String) {
        #expect(ActivityRow.lastComponent(ofPath: path) == "Q3 Roadmap.md")
    }

    ///
    /// A path naming nothing has no filename, which is what makes `init(_:)` refuse the activity rather than draw a blank row.
    ///
    @Test(arguments: ["", "/"])
    func `A path naming nothing reports no file name`(path: String) {
        #expect(ActivityRow.lastComponent(ofPath: path) == nil)
    }

    // MARK: - Initials

    ///
    /// A two-word name gives the first letter of each, uppercased, which is the monogram every card in the design shows.
    ///
    @Test
    func `A first and last name give two initials`() {
        #expect(ActivityRow.initials(forDisplayName: "Anja Kranz") == "AK")
    }

    ///
    /// A three-word name still gives two initials, taken from the outer words rather than the first two, so a middle name does not displace the surname.
    ///
    @Test
    func `A middle name is skipped`() {
        #expect(ActivityRow.initials(forDisplayName: "Maria de Souza") == "MS")
    }

    ///
    /// A single word gives one initial rather than repeating itself.
    ///
    @Test
    func `A single word gives one initial`() {
        #expect(ActivityRow.initials(forDisplayName: "admin") == "A")
    }

    ///
    /// Your own activities carry no actor at all — the server's template reads `You changed {file}` with nothing to resolve — so there is no monogram to draw.
    ///
    @Test
    func `Your own activity has no initials`() {
        #expect(ActivityRow.initials(forDisplayName: nil).isEmpty)
    }

    ///
    /// A display name that is only whitespace or punctuation yields nothing rather than a circle containing a separator.
    ///
    @Test(arguments: ["", "   ", " - "])
    func `A name without letters gives no initials`(displayName: String) {
        #expect(ActivityRow.initials(forDisplayName: displayName).isEmpty)
    }

    ///
    /// An initial is taken as a character rather than a scalar, so a letter built from more than one scalar stays whole instead of being cut in half.
    ///
    @Test
    func `A multi-scalar letter stays whole`() {
        #expect(ActivityRow.initials(forDisplayName: "Ólafur Þórsson") == "ÓÞ")
    }
}
