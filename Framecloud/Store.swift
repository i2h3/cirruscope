import Foundation
import Observation
import os
import Security
import WebKit

///
/// A store that manages the state of the application, including user accounts and navigation.
/// 
@Observable
final class Store {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Store")

    // MARK: State

    ///
    /// The currently setup account, if any.
    ///
    var account: Account?

    ///
    /// Whether the web view currently is in a logout navigation process or not.
    ///
    private(set) var isLoggingOut = false

    // MARK: UserDefaults Keys
    
    private enum UserDefaultsKey {
        static let host = "Host"
        static let user = "User"
    }
    
    init() {
        self.account = loadAccountFromUserDefaults()
    }

    // MARK: - Passwords in Keychain

    func get(passwordOf account: Account) -> String? {
        logger.notice("Getting password of account \(account) from keychain...")

        let service = "Framecloud"
        let accountKey = "\(account.user)@\(account.host.absoluteString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }

        return password
    }

    private func set(password: String, for account: Account) {
        logger.notice("Setting password of account \(account) in keychain...")

        let service = "Framecloud"
        let accountKey = "\(account.user)@\(account.host.absoluteString)"

        guard let passwordData = password.data(using: .utf8) else {
            return
        }

        // First, try to update existing password
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        // If item doesn't exist, add it
        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountKey,
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - UserDefaults Persistence

    private func saveAccountToUserDefaults(_ account: Account) {
        logger.notice("Saving account \(account) to user defaults...")

        UserDefaults.standard.set(account.host.absoluteString, forKey: UserDefaultsKey.host)
        UserDefaults.standard.set(account.user, forKey: UserDefaultsKey.user)
    }
    
    private func loadAccountFromUserDefaults() -> Account? {
        logger.notice("Loading account from user defaults...")

        guard let hostString = UserDefaults.standard.string(forKey: UserDefaultsKey.host),
              let host = URL(string: hostString),
              let user = UserDefaults.standard.string(forKey: UserDefaultsKey.user) else {
            return nil
        }
        
        return Account(host: host, user: user)
    }

    private func removeAccountFromUserDefaults() {
        logger.notice("Removing account from user defaults...")
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.host)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.user)
    }

    // MARK: - Account Management

    func addAccount(host: URL, user: String, password: String) {
        logger.notice("Adding account for \(user) on \(host)...")

        let newAccount = Account(host: host, user: user)
        set(password: password, for: newAccount)
        saveAccountToUserDefaults(newAccount)
        self.account = newAccount
    }

    func beginLogout() {
        logger.notice("Beginning logout...")
        isLoggingOut = true
    }

    func finishLogout() {
        logger.notice("Finishing logout...")

        if let account = self.account {
            removeAccount(account)
        }

        isLoggingOut = false
    }

    func makeInitialRequest() -> URLRequest? {
        guard let account else {
            return nil
        }

        var request = URLRequest(url: account.host)

        guard let password = get(passwordOf: account) else {
            return nil
        }

        let credentials = "\(account.user):\(password)"

        guard let credentialsData = credentials.data(using: .utf8) else {
            return nil
        }

        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        return request
    }

    func removeAccount(_ account: Account) {
        logger.notice("Removing account \(account)...")

        let service = "Framecloud"
        let accountKey = "\(account.user)@\(account.host.absoluteString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        SecItemDelete(query as CFDictionary)

        if self.account?.user == account.user && self.account?.host == account.host {
            removeAccountFromUserDefaults()
            self.account = nil
        }
    }
}
