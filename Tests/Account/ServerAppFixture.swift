// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope

/// `ServerAppFixture` is the corpus of server apps the account suites seed a store with, in the shape `AccountStore.persist(serverApps:)` takes them.
enum ServerAppFixture {
    /// `files` is the app a case reaches for when it needs one app, first both in the server's order and alphabetically.
    static let files = ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files")

    /// `photos` is the second app in menu order, used wherever a case needs a second holder for a shortcut.
    static let photos = ServerAppTransferObject(id: "photos", order: 1, href: "/apps/photos/", name: "Photos")

    /// `talk` is the third app in menu order, and the one a case leaves out of the list when it needs an app the server does not offer.
    static let talk = ServerAppTransferObject(id: "talk", order: 2, href: "/apps/spreed/", name: "Talk")

    /// `all` is the full three-app list a server offers, its names in the same sequence as the positions the server assigned them.
    static let all = [files, photos, talk]

    /// `renamedFiles` is `files` after the server changed everything about it except its identity, so a case can tell an in-place update from a delete-and-reinsert.
    static let renamedFiles = ServerAppTransferObject(id: "files", order: 5, href: "/apps/files/new/", name: "Dateien")

    /// `unalphabeticalApps` are three apps whose server-assigned positions run the exact opposite way to their names, so a case can tell which of the two orderings a list came out in.
    static let unalphabeticalApps = [
        ServerAppTransferObject(id: "talk", order: 0, href: "/apps/spreed/", name: "Talk"),
        ServerAppTransferObject(id: "files", order: 1, href: "/apps/files/", name: "Files"),
        ServerAppTransferObject(id: "deck", order: 2, href: "/apps/deck/", name: "deck"),
    ]

    /// `numberedApps` are two apps whose names differ only in a trailing number, listed with the higher one first.
    static let numberedApps = [
        ServerAppTransferObject(id: "talk10", order: 0, href: "/apps/spreed10/", name: "Talk 10"),
        ServerAppTransferObject(id: "talk2", order: 1, href: "/apps/spreed2/", name: "Talk 2"),
    ]

    /// `sameNameApps` are two apps one server offers under a single display name, listed with the alphabetically later identifier first.
    static let sameNameApps = [
        ServerAppTransferObject(id: "notes-beta", order: 0, href: "/apps/notes-beta/", name: "Notes"),
        ServerAppTransferObject(id: "notes", order: 1, href: "/apps/notes/", name: "Notes"),
    ]
}
