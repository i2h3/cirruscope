import Foundation
import Rainmaker

/// `Settings` provides typed accessors for values persisted in `UserDefaults` and configured statically in the app's `Info.plist`.
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
    }

    /// `InfoPlistKey` collects the string keys under which `Settings` reads statically configured values from the app's `Info.plist`.
    private enum InfoPlistKey {

        /// `minimumSupportedServerMajorVersion` is the key for the `Info.plist` entry that backs `Settings.minimumSupportedServerMajorVersion`.
        static let minimumSupportedServerMajorVersion = "FCMinimumSupportedNextcloudMajorVersion"
    }

    /// `serverAddress` is the URL of the Nextcloud server the user has last connected to, or `nil` while no server has been configured yet.
    ///
    /// `AppDelegate` reads this property during launch to decide which storyboard scene to instantiate.
    /// `ServerAddressViewController` writes to it after successfully reaching and validating a server, and `WebViewController` reads it to load the initial request into its `WKWebView`.
    /// Setting this property to `nil` also clears `themeBackground`, `themeLogo`, and `themeBackgroundPlain` and empties `AssetCache` because those values and the cached image assets describe the server identified by this address and become meaningless without it.
    static var serverAddress: URL? {
        get {
            UserDefaults.standard.url(forKey: UserDefaultsKey.serverAddress.rawValue)
        }

        set {
            if newValue == nil {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverAddress.rawValue)
                themeBackground = nil
                themeLogo = nil
                themeBackgroundPlain = nil
                AssetCache.shared.clear()
            } else {
                UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.serverAddress.rawValue)
            }
        }
    }

    /// `themeBackground` is the `background` value from the server's `Theming` capability, either a URL string pointing to an image or a hex color value, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeBackground: String? {
        get {
            UserDefaults.standard.string(forKey: UserDefaultsKey.themeBackground.rawValue)
        }

        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.themeBackground.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.themeBackground.rawValue)
            }
        }
    }

    /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeLogo: URL? {
        get {
            UserDefaults.standard.url(forKey: UserDefaultsKey.themeLogo.rawValue)
        }

        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.themeLogo.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.themeLogo.rawValue)
            }
        }
    }

    /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability indicating whether the background is a plain color rather than an image, or `nil` while no compatible server has been reached yet.
    ///
    /// `persist(theming:)` writes this property whenever the server's capabilities are successfully retrieved so that other parts of the app can adopt the server's branding without re-fetching the capabilities.
    /// It is cleared together with `serverAddress` when the user disconnects from the server.
    static var themeBackgroundPlain: Bool? {
        get {
            UserDefaults.standard.object(forKey: UserDefaultsKey.themeBackgroundPlain.rawValue) as? Bool
        }

        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.themeBackgroundPlain.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.themeBackgroundPlain.rawValue)
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
            try? await AssetCache.shared.cache(remote: backgroundURL)
        }
        try? await AssetCache.shared.cache(remote: theming.logo)
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
}
