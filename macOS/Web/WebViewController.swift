// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import WebKit

/// `WebViewController` backs the storyboard scene that hosts the embedded `WKWebView` Cirruscope uses to display Nextcloud.
class WebViewController: NSViewController, WKScriptMessageHandler {
    // MARK: - Outlets

    /// `backgroundImageView` is the themed backdrop behind the web view, the server's plain background color or its cached background image or neither, shown while a page loads or after a load fails.
    @IBOutlet
    var backgroundImageView: BackgroundImageView!

    /// `stateOverlay` is the rounded card shown over the themed backdrop while a page loads or after a load fails, holding `progressIndicator`, `headline`, `explanation`, and `retry`.
    @IBOutlet
    var stateOverlay: StateOverlayStackView!

    /// An animated activity indicator.
    ///
    /// Only visible during the initial page load, hidden when a load failed.
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// Multi-functional label for the current state.
    ///
    /// Should be something like "Loading" on window revelation and "Server unreachable" in case of failed page loads.
    @IBOutlet
    var headline: NSTextField!

    /// An optional and longer text to explain the failed page load, if so.
    @IBOutlet
    var explanation: NSTextField!

    /// Optional retry button for failed page loads.
    ///
    /// Visibility depends on the web view state.
    @IBOutlet
    var retry: NSButton!

    /// `webView` is the `WKWebView` that loads `AccountStore.serverAddress` and renders the Nextcloud web interface.
    @IBOutlet
    var webView: WKWebView!

    // MARK: - Logging

    /// `logger` records this web view controller's activity under the `WebViewController` category; it is not `private` so the delegate conformances in `WebViewController+WKNavigationDelegate` and `+WKUIDelegate` can log through it.
    let logger = Logger(for: WebViewController.self)

    /// `nextLogID` hands out the monotonically increasing values behind `logID`, so each `WebViewController` receives a distinct identifier for the lifetime of the process.
    private static var nextLogID: UInt64 = 0

    /// `logID` is a per-instance identifier appended to this controller's log messages, for example "(WebViewController 3)", so entries from different web windows — which each have their own `WebViewController` sharing the `WebViewController` category — can be told apart while the category stays stable and filterable.
    let logID: UInt64 = {
        WebViewController.nextLogID += 1
        return WebViewController.nextLogID
    }()

    // MARK: - Initial Load

    /// `hasRevealedAfterInitialLoad` is `true` once `webView` has been unhidden after its initial navigation has completed.
    var hasRevealedAfterInitialLoad = false

    /// `hasStartedInitialLoad` is `true` once the initial navigation has been issued, so `viewWillAppear()` triggers it exactly once.
    private var hasStartedInitialLoad = false

    /// `pendingRetryURL` is the URL the retry button should reload: the address that last failed to load, or the initial target before the first load has been attempted.
    private var pendingRetryURL: URL?

    /// `retryBudget` decides how this window works through a lapsed browser session: when to re-request a page with the stored app password, when to ask the server whether it still accepts that password, when to hold off, and when to sign out, which it answers only once the server has refused the password with HTTP 401.
    var retryBudget = SilentRetryBudget()

    /// `webWindowController` is the `WebWindowController` hosting this controller, from which the `targetURL` to load is read once the view is in its window.
    private var webWindowController: WebWindowController? {
        view.window?.windowController as? WebWindowController
    }

    /// `restorableURL` is the URL to persist for window restoration: the page currently shown, or the window's target before the first load completes.
    var restorableURL: URL? {
        webView.url ?? webWindowController?.targetURL
    }

    /// `startInitialLoadIfNeeded()` issues the initial navigation the first time the view appears, loading the host window controller's `targetURL` when set or `AccountStore.serverAddress` otherwise.
    private func startInitialLoadIfNeeded() {
        guard hasStartedInitialLoad == false else {
            return
        }

        guard let url = webWindowController?.targetURL ?? AccountStore.shared.serverAddress else {
            preconditionFailure("WebViewController was loaded without a connected server address.")
        }

        hasStartedInitialLoad = true
        pendingRetryURL = url
        logger.info("Starting initial navigation (WebViewController \(self.logID))")
        webView.load(authenticatedRequest(for: url))
    }

    /// `authenticatedRequest(for:)` builds the request that loads `url`, attaching HTTP Basic authentication derived from the `Credentials` stored for the connected server address when they are available.
    func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        if let serverAddress = AccountStore.shared.serverAddress, let credentials = Keychain.credentials(for: serverAddress) {
            request.setValue(credentials.basicAuthorizationValue, forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        enableElementFullscreen()
        makeWebViewResizeWithItsSuperview()
        observeFullscreenState()
        makeWebViewBackgroundTransparent()
        observeWebViewTitle()
        observeWebViewURL()
        installUserScript(Script.localStorageRetention.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        installUserScript(Script.styleSheet.source, injectionTime: .atDocumentStart)
        installAppearanceAttributes()
        installWindowDragBridge()
        installHeaderHeightBridge()
        installSidebarToggleBridge()
        installSidebarShortcutBridge()
        installNotificationBridge()
        observeAppearanceSettings()
        observeAccentColor()
        updateBackdrop()
        updateStateOverlayBackground()

        showLoadingState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        startInitialLoadIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        progressIndicator.startAnimation(self)
    }

    // MARK: - State Overlay

    /// `showLoadingState()` configures `stateOverlay` for an in-progress page load: the spinner and `headline` are shown, `explanation` and `retry` are hidden, and the web view stays hidden behind the background until the load finishes.
    private func showLoadingState() {
        headline.stringValue = String(localized: "Loading…", comment: "Headline shown in the web window while the page is loading.")
        headline.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)
        explanation.isHidden = true
        retry.isHidden = true
        webView.isHidden = true
        updateBackdropVisibility()
        stateOverlay.isHidden = false
    }

    /// `handleNavigationFailure(_:)` switches `stateOverlay` to its failure state — hiding the spinner and showing the "Server unreachable" headline, a friendly explanation, and the retry button — and records the URL a retry should reload.
    func handleNavigationFailure(_ error: any Error) {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        // `WebKitErrorFrameLoadInterruptedByPolicyChange` (102): a navigation cancelled by one of our own policy decisions.
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return
        }

        showFailureState(retrying: nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
    }

    /// `showFailureState(retrying:)` switches `stateOverlay` to its failure state and records `url` as what the retry button reloads, falling back to the page shown, the window's target or the server's address when `url` is `nil`.
    func showFailureState(retrying url: URL?) {
        pendingRetryURL = url
            ?? webView.url
            ?? webWindowController?.targetURL
            ?? AccountStore.shared.serverAddress

        progressIndicator.stopAnimation(self)
        progressIndicator.isHidden = true
        headline.stringValue = String(localized: "Server unreachable", comment: "Headline shown in the web window when a page load failed.")
        headline.isHidden = false
        explanation.stringValue = String(localized: "Check your internet connection and make sure the server is online, then try again.", comment: "Explanation shown in the web window when a page load failed.")
        explanation.isHidden = false
        retry.isHidden = false
        webView.isHidden = true
        updateBackdropVisibility()
        stateOverlay.isHidden = false
    }

    /// `revealLoadedContent()` hides `stateOverlay` and the background and reveals the web view once a navigation has finished.
    func revealLoadedContent() {
        progressIndicator.stopAnimation(self)
        stateOverlay.isHidden = true
        webView.isHidden = false
        updateBackdropVisibility()
        view.window?.makeFirstResponder(webView)
    }

    /// `retryLoad(_:)` re-issues the failed navigation when the user taps the retry button, returning `stateOverlay` to its loading state until the load succeeds or fails again.
    @IBAction
    func retryLoad(_: Any?) {
        guard let url = pendingRetryURL ?? webWindowController?.targetURL ?? AccountStore.shared.serverAddress else {
            return
        }

        logger.info("Retrying navigation to \(url.absoluteString) (WebViewController \(self.logID))")
        retryBudget.reset()
        showLoadingState()
        webView.load(authenticatedRequest(for: url))
    }

    // MARK: - Background

    /// `updateBackdrop()` paints the server's theming background behind the web view, its plain color or the cached copy of its image, or nothing when neither is available so the window material shows through.
    private func updateBackdrop() {
        backgroundImageView.backdropColor = cachedBackgroundColor()
        backgroundImageView.image = cachedBackgroundImage()
    }

    /// `cachedBackgroundColor()` returns the server's plain theming background color, or `nil` when the server publishes an image, no theming has been recorded yet, or the recorded value is not a color.
    private func cachedBackgroundColor() -> NSColor? {
        guard AccountStore.shared.themeBackgroundPlain == true else {
            return nil
        }

        guard let background = AccountStore.shared.themeBackground else {
            return nil
        }

        guard let color = ThemeColor(hexString: background) else {
            logger.error("Theming background is plain but not a hex color, so the backdrop stays empty (WebViewController \(self.logID))")
            return nil
        }

        return NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
    }

    /// `cachedBackgroundImage()` returns the cached theming background image, or `nil` when the server publishes a plain color, the background is not an `http`/`https` image URL, or no cached copy exists yet.
    private func cachedBackgroundImage() -> NSImage? {
        guard AccountStore.shared.themeBackgroundPlain != true, let background = AccountStore.shared.themeBackground, let url = URL(string: background), url.scheme == "http" || url.scheme == "https", let localURL = AssetCache.shared.localURL(for: url)
        else {
            return nil
        }

        return NSImage(contentsOf: localURL)
    }

    // MARK: - Window Title

    /// `titleObservation` retains the key-value observation of `webView`'s `title` that keeps the host window's title in sync with the currently displayed Nextcloud page.
    private var titleObservation: NSKeyValueObservation?

    /// `observeWebViewTitle()` starts mirroring `webView.title` into the host window's title so the page title identifies the window in Mission Control, the "Window" menu, and other system UI, even though the title bar itself hides it.
    private func observeWebViewTitle() {
        titleObservation = webView.observe(\.title, options: [.initial, .new], changeHandler: makeTitleChangeHandler())
    }

    /// `makeTitleChangeHandler()` builds the KVO change handler `observeWebViewTitle()` registers on `webView.title`.
    private nonisolated func makeTitleChangeHandler() -> @Sendable (WKWebView, NSKeyValueObservedChange<String?>) -> Void {
        { [weak self] _, change in
            let title = change.newValue.flatMap(\.self) ?? ""
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Web view title changed to \"\(title)\" (WebViewController \(self.logID))")
                view.window?.title = title
            }
        }
    }

    // MARK: - Web View URL

    /// `urlObservation` retains the key-value observation of `webView`'s `url` that logs every change to the currently displayed page's address.
    private var urlObservation: NSKeyValueObservation?

    /// `observeWebViewURL()` logs `webView.url` on every change so same-document navigations are visible in a log capture.
    private func observeWebViewURL() {
        urlObservation = webView.observe(\.url, options: [.initial, .new], changeHandler: makeURLChangeHandler())
    }

    /// `makeURLChangeHandler()` builds the KVO change handler `observeWebViewURL()` registers on `webView.url`.
    private nonisolated func makeURLChangeHandler() -> @Sendable (WKWebView, NSKeyValueObservedChange<URL?>) -> Void {
        { [weak self] _, change in
            let url = change.newValue.flatMap(\.self)
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Web view URL changed to \(url?.absoluteString ?? "nil") (WebViewController \(self.logID))")
            }
        }
    }

    // MARK: - Fullscreen

    /// `enableElementFullscreen()` turns on WebKit's Fullscreen API for `webView`, so that `Element.requestFullscreen()` — the call behind Nextcloud Talk's "Full screen" button during a call — actually enters fullscreen instead of doing nothing at all (issue #84).
    private func enableElementFullscreen() {
        webView.configuration.preferences.isElementFullscreenEnabled = true
    }

    /// `makeWebViewResizeWithItsSuperview()` replaces the storyboard's four edge constraints on `webView` with an autoresizing mask, so the web view keeps filling whatever view it currently lives in — including the fullscreen window WebKit moves it into.
    private func makeWebViewResizeWithItsSuperview() {
        for constraint in view.constraints where constraint.firstItem === webView || constraint.secondItem === webView {
            constraint.isActive = false
        }

        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = view.bounds
        webView.autoresizingMask = [.width, .height]
    }

    /// `fullscreenStateObservation` retains the key-value observation of `webView`'s `fullscreenState` that logs every transition into and out of WebKit's own fullscreen window.
    private var fullscreenStateObservation: NSKeyValueObservation?

    /// `observeFullscreenState()` logs `webView.fullscreenState` on every change, so that a report of a page's fullscreen button doing nothing — the shape issue #84 arrived in — can be answered from a log capture: whether WebKit was asked at all, whether it entered, and whether it came back.
    private func observeFullscreenState() {
        fullscreenStateObservation = webView.observe(\.fullscreenState, options: [.new], changeHandler: makeFullscreenStateChangeHandler())
    }

    /// `makeFullscreenStateChangeHandler()` builds the KVO change handler `observeFullscreenState()` registers on `webView.fullscreenState`.
    private nonisolated func makeFullscreenStateChangeHandler() -> @Sendable (WKWebView, NSKeyValueObservedChange<WKWebView.FullscreenState>) -> Void {
        { [weak self] _, change in
            guard let state = change.newValue else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.notice("Web view fullscreen state changed to \(Self.name(for: state), privacy: .public) (WebViewController \(self.logID))")
            }
        }
    }

    /// `name(for:)` renders a `WKWebView.FullscreenState` as the stable English identifier `makeFullscreenStateChangeHandler()` writes to the log, the enum being imported from Objective-C and carrying no description of its own, and its raw value alone being unreadable in a capture.
    private static func name(for state: WKWebView.FullscreenState) -> String {
        switch state {
            case .notInFullscreen:
                "notInFullscreen"

            case .enteringFullscreen:
                "enteringFullscreen"

            case .inFullscreen:
                "inFullscreen"

            case .exitingFullscreen:
                "exitingFullscreen"

            @unknown default:
                "unknown (\(state.rawValue))"
        }
    }

    // MARK: - Server App

    /// `currentApp` is the Nextcloud app whose page the web view currently shows, or `nil` when it shows something that is not one of the server's apps.
    var currentApp: ServerAppTransferObject? {
        guard let url = restorableURL else {
            return nil
        }

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return nil
        }

        return AccountStore.shared.serverApps.app(for: url, on: serverAddress)
    }

    // MARK: - Window Dragging

    private func installWindowDragBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.windowDrag.rawValue)
        installUserScript(macOSScript.windowDrag.source, injectionTime: .atDocumentEnd)
    }

    // MARK: - Header Height

    /// `installHeaderHeightBridge()` registers the `headerHeight` message handler and injects `macOSScript.headerHeight`, which measures Nextcloud's header and reports how tall the server draws it.
    private func installHeaderHeightBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.headerHeight.rawValue)
        installUserScript(macOSScript.headerHeight.source, injectionTime: .atDocumentEnd)
    }

    // MARK: - Sidebar

    /// `sidebarToggleAvailable` is `true` while the currently loaded Nextcloud page exposes a sidebar toggle that can be activated.
    var sidebarToggleAvailable = false

    /// `sidebarToggleExpanded` is `true` while Nextcloud's sidebar is currently shown.
    var sidebarToggleExpanded = false

    private func installSidebarToggleBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.sidebarToggleState.rawValue)
        installUserScript(Script.sidebarToggleState.source, injectionTime: .atDocumentEnd)
    }

    /// `installSidebarShortcutBridge()` registers the `sidebarShortcut` message handler and injects `macOSScript.sidebarShortcut`, which claims ⌃⌘S from inside the page for every case in which no `WebWindow` is offered the key equivalent.
    private func installSidebarShortcutBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.sidebarShortcut.rawValue)
        installUserScript(macOSScript.sidebarShortcut.source, injectionTime: .atDocumentStart)
    }

    /// `isSidebarToggleShortcut(_:)` is `true` when `event` is the ⌃⌘S keystroke Cirruscope claims for "Show/Hide Sidebar" ahead of the loaded page.
    static func isSidebarToggleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection([.command, .option, .control, .shift])
        return modifiers == [.control, .command] && event.charactersIgnoringModifiers?.lowercased() == "s"
    }

    @IBAction
    func toggleSidebar(_: Any?) {
        guard let source = Script.sidebarToggle.source else {
            return
        }

        webView.evaluateJavaScript(source)
    }

    // MARK: - Notifications

    /// `installNotificationBridge()` forwards the notifications the web interface raises to `UserNotifier`, asking for notification permission first if the user has not answered yet, so the prompt appears with a server connected.
    private func installNotificationBridge() {
        Task {
            await NotificationAuthorization.requestIfUndetermined(reason: "web window")
        }

        webView.configuration.userContentController.add(self, name: ScriptMessageName.notification.rawValue)
        installUserScript(macOSScript.notificationBridge.source, injectionTime: .atDocumentStart)
    }

    // MARK: - Web View Styling

    /// `makeWebViewBackgroundTransparent()` stops `webView` from painting an opaque background of its own, so the host window's material shines through wherever the loaded page leaves its background transparent.
    private func makeWebViewBackgroundTransparent() {
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
    }

    // MARK: - Appearance

    /// `prefersTranslucentAppearance` is `true` when the translucent appearance is enabled on this device; it defaults to `false` until the user chooses, matching `AppearanceSettingsViewController`.
    private var prefersTranslucentAppearance: Bool {
        AccountStore.shared.translucentAppearance ?? false
    }

    /// `installAppearanceAttributes()` injects a document-start script that seeds `data-cirruscope-translucency`, `data-cirruscope-full-width`, and the accent-color state on `<html>`, so the injected stylesheet's translucency, full-width, and accent rules apply from the first paint without a flash.
    private func installAppearanceAttributes() {
        guard let source = appearanceAttributeScript() else {
            return
        }

        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
    }

    /// `observeAppearanceSettings()` subscribes to `Notification.Name.appearanceSettingsDidChange` so a change made in the Appearance settings tab is applied to this already-open web view without a reload.
    private func observeAppearanceSettings() {
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceSettingsDidChange), name: .appearanceSettingsDidChange, object: nil)
    }

    @objc
    private func appearanceSettingsDidChange() {
        reapplyAppearance()
    }

    /// `reapplyAppearance(windowIsFullScreen:)` re-applies this device's appearance settings, the macOS accent color, and this window's button clearance to the live web view: it rewrites the `<html>` data attributes and the two custom properties the stylesheet keys off — switching translucency, full-width, the accent color, and the header's leading inset without a reload — and updates the native backdrop's visibility.
    func reapplyAppearance(windowIsFullScreen: Bool? = nil) {
        if let source = appearanceAttributeScript(windowIsFullScreen: windowIsFullScreen) {
            webView.evaluateJavaScript(source)
        }

        updateBackdropVisibility()
        updateStateOverlayBackground()
    }

    /// `appearanceAttributeScript(windowIsFullScreen:)` builds the JavaScript that mirrors this device's current appearance settings, the macOS accent color, and this window's button clearance onto `<html>` — as the `data-cirruscope-translucency`, `data-cirruscope-full-width`, `data-cirruscope-accent`, and `data-cirruscope-accent-bright` attributes `Cirruscope.css` scopes its rules to, plus the `--cirruscope-accent-color` custom property it reads the color out of and the `--cirruscope-window-button-clearance` one it insets the header by — or `nil` if the bundled `AppearanceAttributes.js` resource is missing.
    private func appearanceAttributeScript(windowIsFullScreen: Bool? = nil) -> String? {
        guard let script = macOSScript.appearanceAttributes.source else {
            return nil
        }

        let translucency = prefersTranslucentAppearance
        let fullWidth = AccountStore.shared.removeGaps ?? true
        let accentColor = WebAccentColor.effective(in: webView.effectiveAppearance)
        let accentColorArgument = accentColor.map { "'\($0.hexString)'" } ?? "null"
        let accentIsBright = accentColor?.isBright ?? false
        let clearance = windowButtonClearance(windowIsFullScreen: windowIsFullScreen)
        let clearanceArgument = clearance.map { "\($0)" } ?? "null"
        return "\(script)\nwindow.Cirruscope.applyAppearanceAttributes(\(translucency), \(fullWidth), \(accentColorArgument), \(accentIsBright), \(clearanceArgument));"
    }

    /// `windowButtonClearance(windowIsFullScreen:)` is how far in from the leading edge this window's page content must start to clear the standard window buttons, or `nil` while there is no `WebWindow` to ask or AppKit vends it no buttons.
    private func windowButtonClearance(windowIsFullScreen: Bool?) -> CGFloat? {
        guard let window = view.window as? WebWindow else {
            return nil
        }

        return window.windowButtonClearance(isFullScreen: windowIsFullScreen ?? window.styleMask.contains(.fullScreen))
    }

    /// `updateBackdropVisibility()` hides the themed backdrop, color and image alike, whenever the translucent appearance is enabled — so the window material shows through instead of the server's background — or once the web view has been revealed, leaving it visible only behind the loading and failure overlays when translucency is off.
    private func updateBackdropVisibility() {
        backgroundImageView.isHidden = prefersTranslucentAppearance || webView.isHidden == false
    }

    /// `updateStateOverlayBackground()` drops the loading and failure card's opaque fill whenever the translucent appearance is enabled, so the window material shows through it as well.
    private func updateStateOverlayBackground() {
        stateOverlay.drawsBackground = prefersTranslucentAppearance == false
    }

    // MARK: - Accent Color

    /// `observeAccentColor()` subscribes to `Notification.Name.accentColorDidChange` so a new macOS accent-color preference, or a switch between the light and dark appearance, reaches this already-open web view without a reload.
    private func observeAccentColor() {
        NotificationCenter.default.addObserver(self, selector: #selector(accentColorDidChange), name: .accentColorDidChange, object: nil)
    }

    @objc
    private func accentColorDidChange() {
        reapplyAppearance()
    }

    // MARK: - Page Language

    /// `reportPageLanguage()` asks the page that has just finished loading which language the server rendered it in, and hands the answer to `ServerConnection.pageFinishedLoading(in:)`, which refreshes the app list when it changed.
    func reportPageLanguage() {
        guard let query = PageLanguage.query else {
            return
        }

        Task {
            do {
                let language = try await webView.callAsyncJavaScript(query, contentWorld: .page) as? String
                await ServerConnection.pageFinishedLoading(in: language)
            } catch {
                logger.error("Could not read the page's language: \(error.localizedDescription, privacy: .public) (WebViewController \(self.logID))")
            }
        }
    }

    // MARK: - Script Bridge

    /// `ScriptMessageName` is the central list of script-message names that the injected user scripts post back to `userContentController(_:didReceive:)`.
    private enum ScriptMessageName: String {
        /// `windowDrag` is posted by `macOSScript.windowDrag` to ask the host window to begin a drag.
        case windowDrag

        /// `headerHeight` is posted by `macOSScript.headerHeight` to report how tall the server draws Nextcloud's header.
        case headerHeight

        /// `sidebarToggleState` is posted by `macOSScript.sidebarToggleState` to report whether Nextcloud's sidebar toggle is available and expanded.
        case sidebarToggleState

        /// `sidebarShortcut` is posted by `macOSScript.sidebarShortcut` to report that the page has claimed the ⌃⌘S keystroke on the app's behalf.
        case sidebarShortcut

        /// `notification` is posted by `macOSScript.notificationBridge` to forward a web notification's content to the app.
        case notification
    }

    /// `installUserScript(_:injectionTime:forMainFrameOnly:)` registers `source` on the web view's `WKUserContentController` so it runs at `injectionTime` on every page load, in every frame unless `forMainFrameOnly` is `true`, doing nothing if the resource behind it could not be read.
    private func installUserScript(_ source: String?, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool = false) {
        guard let source else {
            return
        }

        let userScript = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        switch ScriptMessageName(rawValue: message.name) {
            case .windowDrag:
                guard let window = view.window, let event = NSApp.currentEvent
                else {
                    return
                }
                window.performDrag(with: event)

            case .headerHeight:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                guard let height = body["height"] as? Double else {
                    return
                }
                NextcloudHeaderHeight.record(CGFloat(height))

            case .sidebarToggleState:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                sidebarToggleAvailable = body["available"] as? Bool ?? false
                sidebarToggleExpanded = body["expanded"] as? Bool ?? false

            case .sidebarShortcut:
                toggleSidebar(nil)

            case .notification:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                UserNotifier.shared.post(title: body["title"] as? String ?? "", body: body["body"] as? String ?? "", tag: body["tag"] as? String ?? "", webNotificationID: body["id"] as? String ?? "", webView: webView)

            case nil:
                break
        }
    }
}
