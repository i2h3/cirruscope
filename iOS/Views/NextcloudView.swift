// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import SwiftUI
import WebKit

/// Hosts the `WebPage` the connected server is shown in, along with the navigation bar and toolbar the app draws around it.
struct NextcloudView: View {
    @Environment(Store.self)
    private var store

    /// Which way text runs, which is what decides whether SwiftUI's leading edge is the physically left one.
    @Environment(\.layoutDirection)
    private var layoutDirection

    /// How many pixels this window's screen draws to the point, which the iPad's View menu is told so its icons are rendered sharp.
    @Environment(\.displayScale)
    private var displayScale

    /// How the app opens an address itself, which for a link off the connected server means handing it to the browser.
    @Environment(\.openURL)
    private var openURL

    /// Whether this window is in front of the user, which is when it serves what Spotlight and the Shortcuts app ask the app to open and reloads a page left blank, and whether it has gone to the background, which is when it stops.
    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var page: WebPage

    /// Carries what the loaded page reports about its app-navigation toggle, which is what decides whether the toolbar control is on screen and how it renders.
    @State
    private var appNavigation: AppNavigationBridge

    /// Carries what the loaded page reports about its notifications menu: which selector found it, and whether its panel is open.
    ///
    /// Nothing on screen is gated on it. It is here so a selector that no longer matches shows up in the log, and so a panel that has just closed can prompt a fresh reading of the unread count.
    @State
    private var notificationsPanel: NotificationsPanelBridge

    /// Decides what the page may navigate to, which is how a sign-in form reached on an expired browser session is turned back into the page the user was on.
    @State
    private var navigationDecider: NextcloudNavigationDecider

    /// The page's own script store, kept so the document-start scripts can be re-registered with a fresh measurement rather than only ever seeded once.
    @State
    private var userContentController: WKUserContentController

    /// The most recent measurement of how much of the web view the app's own interface covers, or `nil` until the first layout pass has produced one.
    @State
    private var insets: WebPageInsets?

    /// Whether this screen has begun its session: loaded its first document, asked for the app list, and started serving what the App Intents layer asks it to open.
    @State
    private var hasStarted = false

    /// Whether a terminated web content process may be answered with a reload at once, which it may from the moment this window comes to the front until it has reloaded once or gone to the background.
    @State
    private var mayReloadAfterTermination = false

    /// Records this screen's activity under the `NextcloudView` category.
    private static let logger = Logger(for: NextcloudView.self)

    /// The name of the function that the bundled `iOSScript.safeAreaInsets` script installs on the page.
    ///
    /// Two callers invoke it with a measurement: the document-start user script that seeds the first one, and the live update that pushes a new one whenever the geometry changes. Nothing checks the name against the script itself, so holding it in one place is what keeps those two from drifting apart.
    private static let safeAreaInsetsEntryPoint = "window.Cirruscope.applySafeAreaInsets"

    /// Decides which of the device's sensors a page is given without WebKit asking first: the camera and the microphone for the connected server, and nothing for anyone else.
    private static var deviceSensorAuthorization: WebPage.DeviceSensorAuthorization {
        WebPage.DeviceSensorAuthorization { permission, frame, origin in
            guard case .mediaCapture = permission else {
                logger.debug("Leaving a request for the motion sensors to WebKit's prompt")
                return .prompt
            }

            let frameOrigin = frame.securityOrigin

            switch MediaCaptureDecision.forRequest(page: (origin.protocol, origin.host, origin.port), frame: (frameOrigin.protocol, frameOrigin.host, frameOrigin.port), connectedTo: AccountStore.shared.serverAddress) {
                case .grant:
                    logger.debug("Page and frame are both on the configured server's origin; granting media capture")
                    return .grant

                case .prompt:
                    logger.debug("Page or frame is not on the configured server's origin, or no server is configured; leaving media capture to WebKit's prompt")
                    return .prompt
            }
        }
    }

    init() {
        var configuration = WebPage.Configuration()
        let appNavigation = AppNavigationBridge()
        let notificationsPanel = NotificationsPanelBridge()
        let navigationDecider = NextcloudNavigationDecider()

        // Completes the user agent into one Safari sends, so Nextcloud does not warn about an unrecognized browser.
        // It has to be set here for the same reason as the handler below, and stays set for the whole session: the
        // Cirruscope name the server associates a login with belongs to the sign-in request, not to this web view.
        configuration.applicationNameForUserAgent = SafariUserAgent.applicationName

        // A call needs both of these. Talk marks its videos `playsinline`, which an iPhone's web view ignores unless
        // inline playback is allowed, so every participant's video would otherwise take over the screen as it starts.
        configuration.deviceSensorAuthorization = Self.deviceSensorAuthorization
        configuration.mediaPlaybackBehavior = .allowsInlinePlayback

        // The handlers have to be on the configuration before the page is built: `WebPage.Configuration` is a struct
        // the page copies at initialization, so one registered afterwards would never reach it. User scripts are not
        // installed here at all — they are installed from the first measurement, which does not exist yet.
        configuration.userContentController.add(appNavigation, name: AppNavigationBridge.messageName)
        configuration.userContentController.add(notificationsPanel, name: NotificationsPanelBridge.messageName)

        // The decider is passed by value and held by the page from here on, which is why it is a reference type: the
        // page it reloads through is the very object being constructed, so it can only be given afterwards, and it
        // holds it weakly for the same reason.
        let page = WebPage(configuration: configuration, navigationDecider: navigationDecider)
        page.isInspectable = true
        navigationDecider.page = page

        _page = State(initialValue: page)
        _appNavigation = State(initialValue: appNavigation)
        _notificationsPanel = State(initialValue: notificationsPanel)
        _navigationDecider = State(initialValue: navigationDecider)
        _userContentController = State(initialValue: configuration.userContentController)
    }

    var body: some View {
        NavigationStack {
            // The web view ignores the safe area so the page paints to the bezel, which leaves it no insets of its own
            // to report. This reader is the sibling that still respects the safe area, and sits at the one place whose
            // insets are the whole of what covers the page: the device's own, plus the navigation bar above it.
            GeometryReader { proxy in
                WebView(page)
                    // `.container` rather than the default of every region: the bare `ignoresSafeArea()` would ignore
                    // the keyboard too, and a focused field in Talk or Text would then sit behind it.
                    .ignoresSafeArea(.container, edges: .all)
                    .webViewMagnificationGestures(.disabled)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .onChange(of: measurement(in: proxy), initial: true) { _, measurement in
                        apply(measurement)
                    }
                    // Over the web view rather than over the `NavigationStack`, so the toolbar above it stays live
                    // while the cover is up: a request that never finishes leaves it up indefinitely, and the way
                    // out of that is the app menu or the account menu. It also takes the web view's own frame,
                    // which is the whole screen — the safe area is ignored just above, so there is no inset here
                    // to leave a strip of blank page showing under the navigation bar or along the bottom edge.
                    //
                    // `isLoading` is WebKit's own answer and the condition is deliberately nothing more. Extending
                    // it to also catch the frame or two between this screen appearing and its first request going
                    // out would trade a flicker nobody sees for a cover that can fail to lift: a load that never
                    // commits leaves `page.url` at `nil` for good, so a condition resting on that would sit over
                    // the failure. What is here clears itself for a failed and a cancelled load alike.
                    //
                    // It follows that this covers document loads only, which is the whole of what empties the
                    // view. Nextcloud's own navigation inside an app — opening a folder in Files, changing
                    // conversation in Talk — is a history entry rather than a request, so nothing goes blank there
                    // and there is nothing to cover.
                    .overlay {
                        LoadingOverlay(isLoading: page.isLoading)
                    }
            }
            .toolbar {
                // Not every Nextcloud app offers an app navigation, so the control leaves the toolbar rather
                // than greying out. `ToolbarContent.hidden(_:)` would say that more directly but is macOS-only —
                // it belongs to toolbar customization, which iOS has no equivalent of — so the item is built
                // conditionally instead.
                if appNavigation.isAvailable {
                    // A `Toggle` rather than a `Button` so the toolbar renders its on state as the selected
                    // glass background: `sidebar.left` has no filled variant to swap to, so reflecting the state
                    // through the symbol would have been a silent no-op. The setter ignores its argument and
                    // only asks the page to toggle — `isExpanded` then follows what the page actually did,
                    // rather than what the tap assumed it would do.
                    ToolbarItem(placement: .navigation) {
                        Toggle(isOn: Binding(get: { appNavigation.isExpanded }, set: { _ in toggleAppNavigation() })) {
                            Label("App Navigation", systemImage: "sidebar.left")
                        }
                        .toggleStyle(.button)
                    }
                }

                ToolbarTitleMenu {
                    ServerAppMenuItems { app in
                        navigateToApp(app)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Offered whether or not anything is unread, so the panel is always one tap away and the
                        // menu's items keep their places; the menu's badge is what says whether anything is waiting.
                        Button {
                            openNotificationsPanel()
                        } label: {
                            Label("Notifications", systemImage: "bell.badge.fill")
                        }

                        Divider()

                        Button {
                            navigate(to: ["settings", "user"])
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }

                        Divider()

                        Button {
                            store.logout()
                        } label: {
                            Label("Logout", systemImage: "iphone.and.arrow.forward.outward")
                        }
                    } label: {
                        if let photo = store.accountPhoto {
                            // A bare image rather than a `Label`, which the bar would draw as a symbol-sized image  inside its padded glass, at the photograph's own proportions.
                            Image(photo, scale: 1, label: Text("Account"))
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFill()
                                // The size the bar draws its glass buttons at, which no API publishes.
                                .frame(width: 44, height: 44)
                                .clipShape(.circle)
                        } else {
                            Label("Account", systemImage: "person.fill")
                        }
                    }
                    // `badge(_:)` draws nothing at all for a count of zero, so what this needs is the value itself
                    // rather than a branch around it.
                    .badge(store.unreadNotificationCount)
                }
                // Only for a photograph, which fills the glass circle edge to edge; the symbol keeps the margins that
                // make its circle as large as its neighbours'.
                .contentMarginsRemoved(store.accountPhoto != nil)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: notificationsPanel.isOpen) { wasOpen, isOpen in
                // A panel that has just closed is a panel notifications may just have been dismissed from. A server
                // without push would otherwise leave the count, and what Notification Center lists, arguing with what
                // the user has just read until the monitor's next poll.
                guard wasOpen, isOpen == false else {
                    return
                }

                store.refreshUnreadNotifications()
            }
        }
        .task(id: insets) {
            // Above the guards, and deliberately: this task's first run is the one with no measurement yet, and it
            // has to be the run that hands the decider what it cannot be built with. Nothing has been loaded at that point, so the
            // decider is holding an account before the first navigation it could be asked about — which is the load
            // below. The store is one object for the life of the app, so assigning it again costs nothing.
            navigationDecider.store = store
            navigationDecider.openURL = openURL

            guard insets != nil else {
                return
            }

            guard hasStarted == false else {
                return
            }

            guard let account = store.account else {
                return
            }

            hasStarted = true
            Self.logger.notice("Starting the session of this screen on its first measurement")
            store.updateApps()

            // Only now, and not when the screen appears: the opener serves at once whatever Spotlight or the Shortcuts
            // app asked for while the app was launching, and that has to wait for the first measurement exactly as
            // the first document does. What was asked for is then that document, rather than a second load straight
            // after the server's own front page.
            guard installEntityOpener() == false else {
                Self.logger.notice("Loaded a request that arrived during launch in place of the server's front page")
                return
            }

            page.load(account.authenticatedRequest(for: account.server))
        }
        // Initially as well, so a window that is already in front when this screen appears may answer a terminated
        // process at once; nothing else here acts before the session has started.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
                case .active:
                    mayReloadAfterTermination = true

                    // A window coming to the front takes over what the App Intents layer asks the app to open, so a
                    // Spotlight result lands in the window the user was last looking at rather than in whichever
                    // appeared first.
                    guard hasStarted else {
                        return
                    }

                    installEntityOpener()

                    // After the opener, so a request it has just loaded is not mistaken for a blank page. This is
                    // what catches a page that went blank while the window was away: a termination heard in the
                    // background, a reload that failed, or a termination no observer was subscribed to hear.
                    reloadIfBlank()

                case .background:
                    mayReloadAfterTermination = false

                    // A window that is closed goes to the background, and that is the one signal it was seen to
                    // give: closing windows under Stage Manager did not run `onDisappear` at all. Handing the job back
                    // here means a closed window is never asked to open anything, and a request arriving while every
                    // window is in the background waits for the one that comes forward.
                    EntityOpening.shared.uninstall(for: page)

                default:
                    break
            }
        }
        .onDisappear {
            // A window whose views are torn down must stop being asked to open things too: its web view is gone from
            // the screen, and a request loaded into it would be a request the user never sees answered.
            EntityOpening.shared.uninstall(for: page)
        }
        .task {
            await followNavigations()
        }
        // Tells the View menu of an iPad's menu bar which page to load a server app into while this window is in
        // front. Withheld until the first measurement for the reason the first load is: nothing may load before the
        // first document can inset itself.
        .focusedSceneValue(insets == nil ? nil : page)
        // Tells the same menu the scale this window's screen draws at. Its content is in no window and would
        // otherwise render the icons at a scale of one, which a 2x or 3x screen then draws blurred. Not withheld with
        // the page: the scale is true from the first layout, and nothing is loaded by it.
        .focusedSceneValue(\.displayScale, displayScale)
    }

    /// What the navigation bar is titled with: the name of the Nextcloud app on screen, or the page's own title where the app cannot be told.
    private var navigationTitle: String {
        guard let url = page.url ?? page.backForwardList.currentItem?.url else {
            return PageTitle.withoutSiteName(page.title)
        }

        guard let app = store.app(for: url) else {
            return PageTitle.withoutSiteName(page.title)
        }

        return app.name
    }

    /// Reads how much of the web view the app's own interface covers out of a layout that still respects the safe area.
    ///
    /// The reader is inset by exactly what covers the page, so its own insets are the measurement. It reports a width of zero until the view has actually been laid out, and that pass is not a measurement: adopting it would release the first load against insets of zero, so the page would parse uninset and be corrected a frame later.
    private func measurement(in proxy: GeometryProxy) -> WebPageInsets? {
        guard proxy.size.width > 0 else {
            return nil
        }

        let safeArea = proxy.safeAreaInsets

        return WebPageInsets(top: safeArea.top, leading: safeArea.leading, bottom: safeArea.bottom, trailing: safeArea.trailing, isRightToLeft: layoutDirection == .rightToLeft)
    }

    /// Adopts a new measurement, so that documents loaded from now on inset themselves as they parse and the one already on screen re-insets itself now.
    private func apply(_ measurement: WebPageInsets?) {
        guard let measurement else {
            return
        }

        guard measurement != insets else {
            return
        }

        insets = measurement

        installUserScripts(with: measurement)
        publishInsets()
    }

    /// Registers every user script the page runs, with `measurement` baked into the one that publishes the insets.
    private func installUserScripts(with measurement: WebPageInsets) {
        userContentController.removeAllUserScripts()

        if let source = Script.localStorageRetention.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        if let source = Script.styleSheet.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if let script = iOSScript.safeAreaInsets.source {
            userContentController.addUserScript(WKUserScript(source: "\(script)\n\(measurement.invocation(of: Self.safeAreaInsetsEntryPoint))", injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if let source = Script.sidebarToggleState.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }

        if let source = iOSScript.notificationsPanelState.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
    }

    /// Publishes the current measurement into the page already on screen.
    ///
    /// The user script covers every document from its own start, so this is what covers the case the user script cannot: a page that is already parsed when the geometry changes under it, which is what a rotation is.
    private func publishInsets() {
        guard let insets else {
            return
        }

        guard let script = iOSScript.safeAreaInsets.source else {
            return
        }

        Task {
            do {
                _ = try await page.callJavaScript("\(script)\n\(insets.invocation(of: Self.safeAreaInsetsEntryPoint))")
            } catch {
                Self.logger.error("Could not publish the safe area insets: \(error.localizedDescription)")
            }
        }
    }

    /// Asks the page that has just finished loading which language the server rendered it in, and hands the answer to `ServerConnection.pageFinishedLoading(in:)`, which refreshes the app list when it changed.
    ///
    /// The same query backs the Mac's web windows, so both apps notice a language change the same way.
    /// A failure is logged and otherwise costs nothing but the refresh, the list then keeping the names it had.
    private func reportPageLanguage() {
        guard let query = PageLanguage.query else {
            return
        }

        Task {
            do {
                let language = try await page.callJavaScript(query) as? String
                await ServerConnection.pageFinishedLoading(in: language)
            } catch {
                Self.logger.error("Could not read the page's language: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Follows this screen's navigations for as long as it is on display: publishing the current measurement again each time a new document commits, reporting the language each finished page was rendered in, and reloading the page once its web content process has been terminated.
    private func followNavigations() async {
        while Task.isCancelled == false {
            do {
                for try await event in page.navigations {
                    switch event {
                        case .committed:
                            publishInsets()

                        case .finished:
                            reportPageLanguage()

                        default:
                            break
                    }
                }

                return
            } catch WebPage.NavigationError.webContentProcessTerminated {
                guard mayReloadAfterTermination else {
                    Self.logger.notice("The web content process was terminated while the window was in the background or had already reloaded since it came to the front; leaving the page until it next does")
                    continue
                }

                Self.logger.notice("The web content process was terminated")
                mayReloadAfterTermination = false
                reloadIfBlank()
            } catch {
                Self.logger.debug("Navigation observation ended with \(error.localizedDescription); subscribing again")
            }
        }
    }

    /// Load something into a page that shows nothing, which is what iOS leaves behind when it ends the page's web content process to reclaim memory, as it does to an app suspended for long enough (issue #119).
    private func reloadIfBlank() {
        guard hasStarted else {
            Self.logger.notice("Not reloading the page, as this screen has not started its session")
            return
        }

        guard page.url == nil else {
            Self.logger.debug("Not reloading the page, as it has an address")
            return
        }

        guard page.isLoading == false else {
            Self.logger.notice("Not reloading the blank page, as a document is on its way in")
            return
        }

        guard let account = store.account else {
            Self.logger.notice("Not reloading the blank page, as no account is configured")
            return
        }

        guard let item = page.backForwardList.currentItem else {
            Self.logger.notice("The page is blank and has no history; loading the server's front page")
            page.load(account.authenticatedRequest(for: account.server))
            return
        }

        Self.logger.notice("The page is blank; loading the one it showed from its history")
        page.load(item)
    }

    /// Ask the page to show or hide Nextcloud's app navigation, by clicking the toggle the web interface offers.
    private func toggleAppNavigation() {
        guard let source = Script.sidebarToggle.source else {
            return
        }

        Task {
            do {
                _ = try await page.callJavaScript(source)
            } catch {
                Self.logger.error("Could not toggle the app navigation: \(error.localizedDescription)")
            }
        }
    }

    /// Ask the page to open Nextcloud's own notifications panel, by clicking the bell the web interface offers in its header.
    private func openNotificationsPanel() {
        guard let source = iOSScript.notificationsPanel.source else {
            return
        }

        Task {
            do {
                _ = try await page.callJavaScript(source)
            } catch {
                Self.logger.error("Could not open the notifications panel: \(error.localizedDescription)")
            }
        }
    }

    /// Load one server app into the web view.
    func navigateToApp(_ app: ServerAppTransferObject) {
        guard let request = store.request(opening: app) else {
            return
        }

        page.load(request)
    }

    /// Make this screen the one that opens what Spotlight, the Shortcuts app and a tapped notification ask for, answering whether it opened a request that was already waiting.
    ///
    /// The page is the owner because it is this window's own and lives exactly as long as the window does, which is what lets the window hand the job back when it closes.
    @discardableResult
    private func installEntityOpener() -> Bool {
        EntityOpening.shared.install(for: page) { request in
            switch request {
                case let .serverApp(app):
                    navigateToApp(app)

                case let .page(target):
                    load(target)
            }
        }
    }

    /// Load one of the connected server's own pages into the web view, named by the path components it lives at.
    private func navigate(to components: [String]) {
        guard let account = store.account else {
            return
        }

        guard let target = SameOriginURL(components: components, relativeTo: account.server) else {
            Self.logger.error("The path \(components.joined(separator: "/")) does not resolve on the connected server; refusing to open it")
            return
        }

        load(target)
    }

    /// Load one address on the connected server into the web view, signed in as the account.
    private func load(_ target: SameOriginURL) {
        guard let account = store.account else {
            return
        }

        guard let proven = SameOriginURL(path: target.url.absoluteString, relativeTo: account.server) else {
            Self.logger.error("A request for an address on another server than the connected one was dropped rather than signed in")
            return
        }

        page.load(account.authenticatedRequest(for: proven.url))
    }
}

// No account, deliberately: with one, the first measurement would load the page from its server and refresh the app
// list into the real store. The title menu's items are previewed on their own in `ServerAppMenuItems.swift` instead.
#Preview {
    NextcloudView()
        .environment(Store())
}
