import Foundation

/// `FramecloudError` is the shared error type for failures originating in app-level code.
///
/// Facilities such as `AssetCache` throw cases of this enum so that error handling at call sites can be uniform across the project.
/// New cases may be added as additional failure modes are introduced.
enum FramecloudError: Error {

    /// `invalidResponse` is thrown when a server returns a response that is not an `HTTPURLResponse`.
    case invalidResponse

    /// `unexpectedStatus` is thrown when a server returns an HTTP status that is neither a 2xx success nor 304 Not Modified.
    case unexpectedStatus(Int)
}
