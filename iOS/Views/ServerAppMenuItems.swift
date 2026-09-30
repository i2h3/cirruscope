// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

///
/// One menu item per server app, each labelled with the app's name and icon, for every menu that offers to open one.
///
/// The navigation bar's title menu and the iPad's View menu list the same apps, in the same order and with the same icons.
/// What differs is which page a chosen app is loaded into, which is handed in, and what the View menu wraps around the list — disabling it while no window in front has a page, and asking for its images to be drawn — so the list itself is written once rather than twice and free to drift.
/// Nothing is listed without an account: the apps are restored from the store and the account from the Keychain, and a backup restored onto another device brings the first without the second, so the sign-in screen would otherwise sit under a menu of items that do nothing.
///
struct ServerAppMenuItems: View {
    ///
    /// What choosing an item does with the app it names.
    ///
    let open: @MainActor (ServerAppTransferObject) -> Void

    ///
    /// The app state the apps, the account and the icon generation are read from.
    ///
    @Environment(Store.self)
    private var store

    ///
    /// How many pixels the screen the list is shown on draws to the point, which is the resolution an icon has to be rendered at to look sharp on it.
    ///
    /// A window supplies it for the title menu. The View menu's content is in no window and would be given SwiftUI's default of one, so `ServerAppCommands` hands it the scale of the window in front instead.
    ///
    @Environment(\.displayScale)
    private var displayScale

    var body: some View {
        if store.account != nil {
            ForEach(store.apps) { app in
                Button {
                    open(app)
                } label: {
                    Label {
                        // The `StringProtocol` overload, so the server's name is shown as it was sent. Interpolating it
                        // into a literal instead would make it a localization key, parsed as Markdown.
                        Text(app.name)
                    } icon: {
                        icon(for: app)
                    }
                }
            }
        }
    }

    ///
    /// The image one server app is listed with: its own, when one has been downloaded, and a generic placeholder when it has not.
    ///
    /// Reading `store.iconGeneration` is what subscribes every menu listing these apps to icons arriving: they live in files shared with the Mac rather than on the apps themselves, so nothing about `store.apps` changes when one lands and observation would otherwise never notice.
    ///
    @ViewBuilder
    private func icon(for app: ServerAppTransferObject) -> some View {
        let _ = store.iconGeneration

        if let account = store.account, let icon = UIImage.serverAppIcon(forAppID: app.id, serverAddress: account.server, scale: displayScale) {
            Image(uiImage: icon)
        } else {
            Image(systemName: "app.grid")
        }
    }
}

// An account is needed for anything to be listed, and one here costs nothing: the list loads nothing itself, and the
// address is on a domain reserved never to resolve.
#Preview {
    Menu {
        ServerAppMenuItems { _ in }
    } label: {
        Text(verbatim: "Apps")
    }
    .environment(Store(account: ServerAccount(server: URL(string: "https://cloud.example.invalid")!, credentials: Credentials(user: "preview", appPassword: "preview")), apps: [
        ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files"),
        ServerAppTransferObject(id: "activity", order: 1, href: "/apps/activity/", name: "Activity"),
    ]))
}
