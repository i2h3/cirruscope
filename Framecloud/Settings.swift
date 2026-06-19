import Foundation

/// `Settings` provides typed accessors for values persisted in `UserDefaults` and configured statically in the app's `Info.plist`.
///
/// `AppDelegate` consults `Settings.serverAddress` on launch to choose between presenting `ServerAddressViewController` and `WebViewController`.
/// `ServerAddressViewController` writes the user's chosen server address back to `Settings` after validating it against `Settings.minimumSupportedServerMajorVersion`, and `WebViewController` reads the address again to load the initial request.
enum Settings {

    /// `UserDefaultsKey` enumerates the raw string keys under which `Settings` stores user-specific values in `UserDefaults`.
    private enum UserDefaultsKey: String {

        /// `serverAddress` is the key under which `Settings.serverAddress` persists the URL of the Nextcloud server the user has connected to.
        case serverAddress
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
    static var serverAddress: URL? {
        get {
            UserDefaults.standard.url(forKey: UserDefaultsKey.serverAddress.rawValue)
        }

        set {
            if newValue == nil {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverAddress.rawValue)
            } else {
                UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.serverAddress.rawValue)
            }
        }
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
