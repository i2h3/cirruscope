import Foundation

/// `CirruscopeError` is the shared error type for failures originating in app-level code.
///
/// Facilities such as `AssetCache`, `Keychain`, and the Login Flow v2 integration throw cases of this enum so that error handling at call sites can be uniform across the project.
/// It conforms to `LocalizedError` so the messages presented to the user via `error.localizedDescription` are meaningful.
/// New cases may be added as additional failure modes are introduced.
enum CirruscopeError: Error, LocalizedError {

    /// `invalidResponse` is thrown when a server returns a response that is not an `HTTPURLResponse`.
    case invalidResponse

    /// `unexpectedStatus` is thrown when a server returns an HTTP status that is neither a 2xx success nor 304 Not Modified.
    case unexpectedStatus(Int)

    /// `keychainFailure` is thrown when the macOS Keychain rejects a write performed by `Keychain`, carrying the underlying `OSStatus`.
    case keychainFailure(OSStatus)

    /// `loginPresentationFailed` is thrown when the `ASWebAuthenticationSession` that drives Login Flow v2 cannot be presented.
    case loginPresentationFailed

    /// `loginCancelled` is thrown when the user dismisses the Login Flow v2 grant sheet before completing it.
    case loginCancelled

    /// `loginTimedOut` is thrown when the Login Flow v2 grant is not completed within the polling deadline.
    case loginTimedOut

    var errorDescription: String? {
        switch self {
            case .invalidResponse:
                "The server returned a response that could not be understood."

            case let .unexpectedStatus(code):
                "The server returned an unexpected status code (\(code))."

            case let .keychainFailure(status):
                "The login credentials could not be stored in the keychain (status \(status))."

            case .loginPresentationFailed:
                "The login window could not be opened."

            case .loginCancelled:
                "The login was cancelled."

            case .loginTimedOut:
                "The login timed out before it was completed. Please try again."
        }
    }
}
