// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreSpotlight
import os
import SwiftUI

struct ContentView: View {
    ///
    /// Records what a Spotlight continuation did, under the `ContentView` category.
    ///
    /// Static because the view is a value type rebuilt on every body evaluation, and because the continuation handler is the only thing here that logs.
    ///
    private static let logger = Logger(for: ContentView.self)

    @Environment(Store.self)
    private var store

    var body: some View {
        Group {
            if store.account == nil {
                ServerAddressView()
            } else {
                NextcloudView()
            }
        }
        // A Spotlight result the user picked. App Intents does not run the matching `Open…Intent` on the app's
        // behalf for a donated item, so the system foregrounds the app and hands it the selection to act on;
        // reading which entity it names and what opens it is `SpotlightSelection`, shared with the Mac, which
        // receives the same activity through its application delegate instead.
        // It is handed to `EntityOpening` rather than acted on here, for the same reason the intents hand it
        // there: this view has no web view to load anything into, and on a cold launch there is not yet a screen
        // that does.
        // Written to tolerate the system also running the intent, which would arrive at the same place: opening
        // one thing twice loads one request twice, and the second is the same page as the first.
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            guard let request = SpotlightSelection.request(from: userActivity) else {
                // Deliberately logged rather than returned silently. This branch is where every donated entity
                // other than a server app used to end up, and its silence is why that read as the app doing
                // nothing rather than as the app refusing something.
                Self.logger.notice("A Spotlight selection resolved to nothing this screen can open")
                return
            }

            Self.logger.notice("Handing a Spotlight selection to the entity opener")
            EntityOpening.shared.open(request)
        }
    }
}
