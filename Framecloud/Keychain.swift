import Foundation

/// `Keychain` stores the `Credentials` obtained from Login Flow v2 in the macOS Keychain, keyed by the address of the server they authenticate against.
///
/// `ServerAddressViewController` writes credentials here after a successful login, `ServerConnection.authenticated(address:)` and `WebViewController` read them back, and `Settings.serverAddress`'s setter clears them when the user disconnects.
/// Items use the app's default Keychain access group, so no `keychain-access-groups` entitlement is required under the App Sandbox.
enum Keychain {

    /// `service` is the constant `kSecAttrService` value under which every credential item is filed, so the app's items can be enumerated and cleared as a group.
    private static let service = "Framecloud"

    /// `store(_:for:)` persists `credentials` for `server`, replacing any credentials previously stored for the same server.
    ///
    /// It throws `FramecloudError.keychainFailure` if the Keychain rejects the write.
    static func store(_ credentials: Credentials, for server: URL) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw FramecloudError.keychainFailure(status)
        }
    }

    /// `credentials(for:)` returns the credentials stored for `server`, or `nil` if none have been stored or the stored value cannot be decoded.
    static func credentials(for server: URL) -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    /// `clearAll()` removes every credential item the app has stored.
    ///
    /// `Settings.serverAddress`'s setter calls this when the address is cleared so that no credentials remain for a server the app no longer talks to.
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
