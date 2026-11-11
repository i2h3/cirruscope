// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WebKit

/// The server apps in the View menu of an iPad's menu bar, each loading into whichever window is in front.
struct ServerAppCommands: Commands {
    /// The app state the list is drawn from, handed in because commands sit beside the windows and inherit none of the environment their content is given.
    let store: Store

    /// The web page of the window in front, or `nil` while no window in front has one.
    @FocusedValue(WebPage.self)
    private var page

    /// How many pixels the screen of the window in front draws to the point, or `nil` while no window in front has said.
    @FocusedValue(\.displayScale)
    private var displayScale

    var body: some Commands {
        // After the sidebar group, which is where the Mac's storyboard puts the same section: after Show Sidebar,
        // bracketed by separators of its own. The app has no sidebar of its own on iPad, so the anchor is only a place.
        CommandGroup(after: .sidebar) {
            ServerAppMenuItems { app in
                open(app)
            }
            .disabled(page == nil)
            // iPadOS 27 hides the images of menu bar items by default, and SwiftUI turns this label style into the
            // preference that shows them anyway — the same exception the Mac's View menu makes for these items alone.
            .labelStyle(.titleAndIcon)
            // The icons are bitmaps rendered at the display scale their view is given, and this content is given
            // SwiftUI's default of one, being in no window. The window in front knows its screen's real scale.
            .transformEnvironment(\.displayScale) { scale in
                if let displayScale {
                    scale = displayScale
                }
            }
            .environment(store)
        }
    }

    /// Load `app` into the window in front.
    private func open(_ app: ServerAppTransferObject) {
        guard let page else {
            return
        }

        guard let request = store.request(opening: app) else {
            return
        }

        page.load(request)
    }
}
