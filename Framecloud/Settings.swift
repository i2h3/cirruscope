import Foundation

final class Settings {
    private enum UserDefaultsKey: String {
        case serverAddress
    }

    private enum InfoPlistKey {
        static let minimumSupportedServerMajorVersion = "FCMinimumSupportedNextcloudMajorVersion"
    }

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
