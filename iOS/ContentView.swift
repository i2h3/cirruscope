// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreSpotlight
import SwiftUI

struct ContentView: View {
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
        // A Spotlight result the user picked. App Intents does not run `OpenServerAppIntent` on the app's behalf
        // for a donated item, so the system foregrounds the app and hands it the selection to act on; reading which
        // entity it names is `SpotlightSelection`, shared with the Mac, which receives the same activity through
        // its application delegate instead.
        // It is handed to `EntityOpening` rather than acted on here, for the same reason the intent hands it there:
        // this view has no web view to load anything into, and on a cold launch there is not yet a screen that does.
        // Written to tolerate the system also running the intent, which would arrive at the same place: opening one
        // app twice loads one request twice, and the second is the same page as the first.
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            guard let app = SpotlightSelection.serverApp(from: userActivity) else {
                return
            }

            EntityOpening.shared.open(app)
        }
    }
}
