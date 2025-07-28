import Foundation

///
/// Represents a user account on a remote host stored locally.
///
struct Account {
    let host: URL
    let user: String
}

///
/// Prettier description for debugging.
///
extension Account: CustomStringConvertible {
    var description: String {
        "\(user)@\(host)"
    }
}
