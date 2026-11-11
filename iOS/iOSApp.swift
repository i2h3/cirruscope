// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import SwiftUI

/// The iOS app itself, which builds the app state from the credentials the device already holds and hands it to every window.
@main
struct iOSApp: App {
    /// Records what each scene phase set in motion, under the `iOSApp` category.
    private static let logger = Logger(for: iOSApp.self)

    /// Global app state, built from whatever credentials this device already holds and handed to every screen and to the menu bar's commands.
    let store = Store.restored()

    /// Install the notification center delegate, which must be in place before launch finishes to receive the tap on a notification that launched the app.
    ///
    /// The app has no application delegate, and this is the earliest point SwiftUI runs its code, during every launch, a background launch included.
    init() {
        UserNotificationDelegate.shared.configure()
    }

    /// Whether the app is in front of the user, which is what the notification monitor and the background refresh both hang off.
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        // The server apps in the View menu of an iPad's menu bar. An iPhone has no menu bar, and no item here carries
        // a keyboard shortcut, so nothing of this reaches the key commands SwiftUI builds there instead.
        .commands {
            ServerAppCommands(store: store)
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

    /// React to the app arriving in front of the user, or leaving.
    private func handle(_ phase: ScenePhase) {
        switch phase {
            case .active:
                Self.logger.notice("The app became active\(self.store.account == nil ? " with no account configured" : "", privacy: .public)")
                arm()
                store.startNotificationMonitor()

                // Donates the persisted apps to Spotlight and refreshes the values the Shortcuts app offers for the
                // action's parameter. There is no once-per-launch hook on this platform the way macOS has
                // `applicationDidFinishLaunching(_:)`, so it is called on every activation and is a no-op after the
                // first — which also means the first donation happens from what was persisted, before the server
                // has been asked anything.
                Self.logger.notice("Starting the Spotlight indexers; each is a no-op after the first activation")
                ServerAppIndexer.shared.start()
                ConversationIndexer.shared.start()
                NoteIndexer.shared.start()
                CollectiveIndexer.shared.start()

                Task {
                    await NotificationRefreshTask.logPendingRequests()
                }

            case .background:
                Self.logger.notice("The app went to the background")
                arm()
                NotificationMonitor.shared.suspend()

            default:
                break
        }
    }

    /// Ask for the next background wake-up, or withdraw the request when there is nothing to wake for.
    private func arm() {
        guard store.account != nil else {
            NotificationRefreshTask.cancelRequest()
            return
        }

        NotificationRefreshTask.submitRequest(reason: "scene phase")
    }
}
