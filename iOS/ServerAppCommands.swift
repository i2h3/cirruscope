// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WebKit

///
/// The server apps in the View menu of an iPad's menu bar, each loading into whichever window is in front.
///
/// The Mac builds the same list into its own View menu and brings forward a window already showing the chosen app. An iPad window is a scene this app does not track, so the counterpart here loads the app into the window the user is looking at, which is what that window's own title menu does too.
/// That window is found through its web page, which `NextcloudView` publishes as a focused scene value. A scene value rather than a focused one, because focus inside the web view belongs to WebKit's own first responder and SwiftUI's focus never sees it; and the page rather than a closure, because an object keeps its identity for the life of its window, so the menu is rebuilt when the window in front changes rather than every time a view redraws.
/// The same window also says what scale its screen draws at, because this content is in no window and would otherwise render the icons at a scale of one.
/// The items are disabled while no window in front has a page, keeping their place in the menu rather than coming and going; signed out, `ServerAppMenuItems` lists none at all.
///
struct ServerAppCommands: Commands {
    ///
    /// The app state the list is drawn from, handed in because commands sit beside the windows and inherit none of the environment their content is given.
    ///
    let store: Store

    ///
    /// The web page of the window in front, or `nil` while no window in front has one.
    ///
    @FocusedValue(WebPage.self)
    private var page

    ///
    /// How many pixels the screen of the window in front draws to the point, or `nil` while no window in front has said.
    ///
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
            // On iPadOS 26, which shows them regardless, it changes nothing.
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

    ///
    /// Load `app` into the window in front.
    ///
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
