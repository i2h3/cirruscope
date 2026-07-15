// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `Settings` provides typed accessors for values persisted in a `UserDefaults` suite scoped to `AppGroup.identifier` — so a future app extension sharing the same App Group can read and write the same settings — and configured statically in the app's `Info.plist`.
///
/// `AppDelegate` consults `Settings.serverAddress` on launch to choose between presenting `ServerAddressViewController` and `WebViewController`.
/// `ServerAddressViewController` writes the user's chosen server address back to `Settings` after validating it against `Settings.minimumSupportedServerMajorVersion`, and `WebViewController` reads the address again to load the initial request.
/// `AppDelegate` and `ServerAddressViewController` additionally feed the server's `Theming` capability into `persist(theming:)` whenever they successfully retrieve the capabilities, which mirrors the relevant properties into `themeBackground`, `themeLogo`, and `themeBackgroundPlain` and asks `AssetCache` to download the referenced image assets. Those values are cleared together with `serverAddress` when the user disconnects.
enum Settings {
    /// `UserDefaultsKey` enumerates the raw string keys under which `Settings` stores user-specific values in `UserDefaults`.
    private enum UserDefaultsKey: String {
        /// `serverAddress` is the key under which `Settings.serverAddress` persists the URL of the Nextcloud server the user has connected to.
        case serverAddress

        /// `themeBackground` is the key under which `Settings.themeBackground` persists the `background` property of the server's `Theming` capability.
        case themeBackground

        /// `themeLogo` is the key under which `Settings.themeLogo` persists the `logo` URL of the server's `Theming` capability.
        case themeLogo

        /// `themeBackgroundPlain` is the key under which `Settings.themeBackgroundPlain` persists the `backgroundPlain` flag of the server's `Theming` capability.
        case themeBackgroundPlain

        /// `serverVersion` is the key under which `Settings.serverVersion` persists the human-readable version string of the connected server.
        case serverVersion

        /// `serverApps` is the key under which `Settings.serverApps` persists the list of Nextcloud server apps offered by the connected server.
        case serverApps

        /// `appShortcuts` is the key under which `Settings.appShortcuts` persists the user's custom keyboard shortcuts for individual server apps.
        case appShortcuts
    }

    /// `InfoPlistKey` collects the string keys under which `Settings` reads statically configured values from the app's `Info.plist`.
    private enum InfoPlistKey {
        /// `minimumSupportedServerMajorVersion` is the key for the `Info.plist` entry that backs `Settings.minimumSupportedServerMajorVersion`.
        static let minimumSupportedServerMajorVersion = "MinimumSupportedNextcloudMajorVersion"

        /// `privacyPolicy` is the key for the `Info.plist` entry that backs `Settings.privacyPolicy`.
        static let privacyPolicy = "PrivacyPolicy"

        /// `supportURL` is the key for the `Info.plist` entry that backs `Settings.supportURL`.
        static let supportURL = "SupportURL"
    }

    /// `logger` records settings persistence failures — JSON coding and theming asset caching — under the `Settings` category.
    private static let logger = Logger(for: Settings.self)

    /// `defaults` is the shared `UserDefaults` suite backing every property below, scoped to `AppGroup.identifier` so a future app extension sharing the same App Group can read and write the same settings.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` does not conform to `Sendable`, even though it is documented as thread-safe internally; this mirrors `Rainmaker.Server`'s own `nonisolated(unsafe) let fileManager = FileManager.default` for the same reason.
    private nonisolated(unsafe) static let defaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: AppGroup.identifier) else {
            preconditionFailure("Could not create the UserDefaults suite for App Group \"\(AppGroup.identifier)\".")
        }

        return suite
    }()

    /// `serverAddress` is the URL of the Nextcloud server the user has last connected to, or `nil` while no server has been configured yet.
    ///
    /// `AppDelegate` reads this property during launch to decide which storyboard scene to instantiate.
    /// `ServerAddressViewController` writes to it after successfully reaching and validating a server, and `WebViewController` reads it to load the initial request into its `WKWebView`.
    /// Setting this property to `nil` also clears `themeBackground`, `themeLogo`, `themeBackgroundPlain`, `serverVersion`, and `serverApps`, empties `AssetCache`, and clears the stored Login Flow v2 credentials via `Keychain` because those values, cached assets, and credentials describe the server identified by this address and become meaningless without it.
    static var serverAddress: URL? {
        get {
            defaults.url(forKey: UserDefaultsKey.serverAddress.rawValue)
        }

        set {
            if newValue == nil {
                defaults.removeObject(forKey: UserDefaultsKey.serverAddress.rawValue)
                themeBackground = nil
                themeLogo = nil
                themeBackgroundPlain = nil
                serverVersion = nil
                serverApps = []
                AssetCache.shared.clear()
                Keychain.clearAll()
            } else {
                defaults.set(newValue, forKey: UserDefaultsKey.serverAddress.rawValue)
            }
        }
    }

    /// `themeBackground` is the `background` value from the server's `Theming` capability, either a URL string pointing to an image or a hex color value, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeBackground: String? {
        get {
            defaults.string(forKey: UserDefaultsKey.themeBackground.rawValue)
        }

        set {
            if let newValue {
                defaults.set(newValue, forKey: UserDefaultsKey.themeBackground.rawValue)
            } else {
                defaults.removeObject(forKey: UserDefaultsKey.themeBackground.rawValue)
            }
        }
    }

    /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeLogo: URL? {
        get {
            defaults.url(forKey: UserDefaultsKey.themeLogo.rawValue)
        }

        set {
            if let newValue {
                defaults.set(newValue, forKey: UserDefaultsKey.themeLogo.rawValue)
            } else {
                defaults.removeObject(forKey: UserDefaultsKey.themeLogo.rawValue)
            }
        }
    }

    /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability indicating whether the background is a plain color rather than an image, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeBackgroundPlain: Bool? {
        get {
            defaults.object(forKey: UserDefaultsKey.themeBackgroundPlain.rawValue) as? Bool
        }

        set {
            if let newValue {
                defaults.set(newValue, forKey: UserDefaultsKey.themeBackgroundPlain.rawValue)
            } else {
                defaults.removeObject(forKey: UserDefaultsKey.themeBackgroundPlain.rawValue)
            }
        }
    }

    /// `serverVersion` is the human-readable version string of the connected Nextcloud server, or `nil` while no supported server has been reached yet.
    ///
    /// `ServerConnection.validate(_:)` writes it whenever a supported server's capabilities are retrieved.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var serverVersion: String? {
        get {
            defaults.string(forKey: UserDefaultsKey.serverVersion.rawValue)
        }

        set {
            if let newValue {
                defaults.set(newValue, forKey: UserDefaultsKey.serverVersion.rawValue)
            } else {
                defaults.removeObject(forKey: UserDefaultsKey.serverVersion.rawValue)
            }
        }
    }

    /// `persist(theming:)` mirrors the values of `theming` into `themeBackground`, `themeLogo`, and `themeBackgroundPlain` and awaits the `AssetCache` downloads of the background image and the logo so the cached files are ready by the time the call returns.
    ///
    /// `AppDelegate` and `ServerAddressViewController` await this whenever they successfully retrieve the server's capabilities, before they proceed to present any UI that relies on the cached branding assets.
    /// The background download is skipped when `theming.background` does not parse to a URL with an `http` or `https` scheme because the server then publishes a color value rather than an image.
    static func persist(theming: Theming) async {
        themeBackground = theming.background
        themeLogo = theming.logo
        themeBackgroundPlain = theming.backgroundPlain

        if let backgroundURL = URL(string: theming.background), backgroundURL.scheme == "http" || backgroundURL.scheme == "https" {
            do {
                try await AssetCache.shared.cache(remote: backgroundURL)
            } catch {
                logger.notice("Could not cache theming background: \(error.localizedDescription)")
            }
        }

        do {
            try await AssetCache.shared.cache(remote: theming.logo)
        } catch {
            logger.notice("Could not cache theming logo: \(error.localizedDescription)")
        }
    }

    /// `serverApps` is the list of Nextcloud server apps offered by the connected server, sorted ascending by their `order`.
    ///
    /// `persist(navigationApps:)` writes it whenever the apps are fetched, and `AppDelegate` reads it to build the View and Dock menus and `ServerAppsViewController` to list the apps in settings.
    /// Setting it prunes `appShortcuts` entries for apps that are no longer offered and posts `Notification.Name.serverAppsDidChange`.
    static var serverApps: [ServerApp] {
        get {
            guard let data = defaults.data(forKey: UserDefaultsKey.serverApps.rawValue) else {
                return []
            }

            do {
                return try JSONDecoder().decode([ServerApp].self, from: data)
            } catch {
                logger.error("Could not decode stored server apps: \(error.localizedDescription)")
                return []
            }
        }

        set {
            do {
                try defaults.set(JSONEncoder().encode(newValue), forKey: UserDefaultsKey.serverApps.rawValue)
            } catch {
                logger.error("Could not encode server apps: \(error.localizedDescription)")
            }

            let availableIDs = Set(newValue.map(\.id))
            let prunedShortcuts = appShortcuts.filter { availableIDs.contains($0.key) }

            if prunedShortcuts.count != appShortcuts.count {
                appShortcuts = prunedShortcuts
            }

            // `Settings` is nonisolated and this setter can be reached from a background context (e.g. via
            // `ServerConnection.refreshNavigationApps(using:)` right after signing in), but `AppDelegate` observes
            // this notification with a plain selector (no `queue: .main`) and dispatches straight into `@MainActor`
            // code, so the post itself must land on the main thread regardless of the calling thread.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)
            }
        }
    }

    /// `appShortcuts` maps a `ServerApp.id` to the `KeyboardShortcut` the user has assigned to it; apps without an entry have no shortcut.
    ///
    /// `ServerAppsViewController` writes it as the user edits shortcuts, and `AppDelegate` reads it to set the key equivalents of the server-app menu items.
    /// Setting it posts `Notification.Name.serverAppsDidChange`.
    static var appShortcuts: [String: KeyboardShortcut] {
        get {
            guard let data = defaults.data(forKey: UserDefaultsKey.appShortcuts.rawValue) else {
                return [:]
            }

            do {
                return try JSONDecoder().decode([String: KeyboardShortcut].self, from: data)
            } catch {
                logger.error("Could not decode stored app shortcuts: \(error.localizedDescription)")
                return [:]
            }
        }

        set {
            do {
                try defaults.set(JSONEncoder().encode(newValue), forKey: UserDefaultsKey.appShortcuts.rawValue)
            } catch {
                logger.error("Could not encode app shortcuts: \(error.localizedDescription)")
            }

            // See the matching comment in `serverApps`'s setter: this post must land on the main thread regardless
            // of the calling thread, since `AppDelegate` observes it with a plain selector into `@MainActor` code.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)
            }
        }
    }

    /// `persist(navigationApps:)` projects `navigationApps` into `ServerApp` values, sorts them by `order`, and stores them in `serverApps`.
    ///
    /// `ServerConnection.refreshNavigationApps(using:)` calls it whenever the server's navigation apps have been fetched, which also prunes shortcuts for apps that are no longer offered.
    static func persist(navigationApps: [NavigationItem]) {
        serverApps = navigationApps.map(ServerApp.init).sorted { $0.order < $1.order }
    }

    /// `minimumSupportedServerMajorVersion` is the lowest Nextcloud major version the app accepts.
    ///
    /// `ServerAddressViewController` consults this value after fetching the server's capabilities via `Rainmaker` and rejects servers running an older major release.
    static var minimumSupportedServerMajorVersion: Int {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.minimumSupportedServerMajorVersion) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.minimumSupportedServerMajorVersion)\" entry.")
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }

        preconditionFailure("Info.plist entry \"\(InfoPlistKey.minimumSupportedServerMajorVersion)\" must be an integer or a string representing one but was \(type(of: value)).")
    }

    /// `privacyPolicy` is the URL of Cirruscope's online privacy policy.
    ///
    /// `AppDelegate.openPrivacyPolicy(_:)` opens it in the user's default browser when the user chooses the Help-menu item or the button on `ServerAddressViewController`.
    static var privacyPolicy: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.privacyPolicy) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.privacyPolicy)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.privacyPolicy)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    /// `supportURL` is the URL of Cirruscope's online support page.
    ///
    /// `AppDelegate.openSupportPage(_:)` opens it in the user's default browser when the user chooses the Help-menu item.
    static var supportURL: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.supportURL) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.supportURL)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.supportURL)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }
}

extension Notification.Name {
    /// `serverAppsDidChange` is posted by `Settings` whenever `serverApps` or `appShortcuts` changes so `AppDelegate` can rebuild the View and Dock menus.
    static let serverAppsDidChange = Notification.Name("ServerAppsDidChange")

    /// `downloadsDidChange` is posted by `DownloadManager` whenever its `downloads` list or a download's state changes so `DownloadViewController` can reload its table.
    static let downloadsDidChange = Notification.Name("DownloadsDidChange")

    /// `downloadDidStart` is posted by `DownloadManager` when a new transfer begins so `AppDelegate` can open and bring the Downloads window to the foreground.
    static let downloadDidStart = Notification.Name("DownloadDidStart")
}
