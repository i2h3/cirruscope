// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

///
/// The iOS app itself.
///
@main
struct iOSApp: App {
    ///
    /// Global app state, built from whatever credentials this device already holds and handed to every screen.
    ///
    let store = Store.restored()

    ///
    /// Whether the app is in front of the user, which is what both halves of the notification refresh hang off.
    ///
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        // Registers `NotificationRefreshTask.identifier` with `BGTaskScheduler` while this scene is built, which
        // happens inside launch — the deadline registration has, and the reason no application delegate is needed to
        // meet it. SwiftUI also owns the expiration handler and the completion call that `BGTaskScheduler.register`
        // would leave to its caller, and forgetting either of those is documented to get an app killed.
        //
        // The action is not inferred main-actor despite `body` being main-actor-isolated by the SDK: the parameter
        // type is `@Sendable`, and a `@Sendable` closure never inherits the isolation it is written in. That is what
        // makes this safe where a `BGTaskScheduler.register` launch handler — a plain, non-`@Sendable` closure the
        // system invokes off-main — would trap at its own entry point. See AGENTS.md → Concurrency for that shape
        // and the crash it caused.
        .backgroundTask(.appRefresh(NotificationRefreshTask.identifier)) {
            await NotificationRefreshTask.run()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            handle(phase)
        }
    }

    ///
    /// React to the app arriving in front of the user, or leaving.
    ///
    /// Arriving is the whole of the foreground refresh: on launch and on every return, with no timer and no push. It re-arms the background task as well, which closes the hole that arming on the way out alone would leave — pending task requests do not survive a restart of the device, so an app arming only as it is backgrounded would go unarmed from a reboot until its next full session.
    /// Leaving arms it too, and that is not redundant: it is the last moment the app knows whether there is an account to fetch for, and a second submission for one identifier replaces the pending request rather than adding to it.
    /// `.inactive` is deliberately not acted on. It is passed through in both directions, and it is also what a pulled-down Notification Center produces, so treating it as either edge would fire on gestures that never left the app.
    ///
    private func handle(_ phase: ScenePhase) {
        switch phase {
            case .active:
                arm()
                store.refreshUnreadNotifications()

                Task {
                    await NotificationRefreshTask.logPendingRequests()
                }

            case .background:
                arm()

            default:
                break
        }
    }

    ///
    /// Ask for the next background wake-up, or withdraw the request when there is nothing to wake for.
    ///
    private func arm() {
        guard store.account != nil else {
            NotificationRefreshTask.cancelRequest()
            return
        }

        NotificationRefreshTask.submitRequest(reason: "scene phase")
    }
}
