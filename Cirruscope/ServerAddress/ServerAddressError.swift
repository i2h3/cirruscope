// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAddressError` is the reason `ServerAddress(normalizing:)` could not turn what the user typed into an address to connect to.
enum ServerAddressError: Error, Equatable, LocalizedError {
    /// `empty` is thrown when the input holds nothing but whitespace, or nothing at all.
    case empty

    /// `tooLong` is thrown when the input exceeds `ServerAddress.maximumLength` characters.
    case tooLong

    /// `invalidCharacters` is thrown when the input still holds control characters after the invisible and line-breaking ones a paste carries have been removed.
    case invalidCharacters

    /// `unsupportedScheme` is thrown when the input names a scheme other than HTTP or HTTPS, carrying it in lowercase for the message.
    case unsupportedScheme(String)

    /// `credentialsInAddress` is thrown when the input carries a user name or a password.
    case credentialsInAddress

    /// `malformed` is thrown when the input cannot be parsed as a URL at all, carrying the sanitized input for the message.
    ///
    /// Foundation is the judge here, and it is stricter than it looks in exactly one place that matters: a space inside a host makes the whole value unparseable, while a space in a path is accepted and percent-encoded.
    case malformed(String)

    /// `missingHost` is thrown when the input parses but names no server, as `https://` and `/nextcloud` do.
    case missingHost

    /// `invalidHost` is thrown when the host cannot name a server, carrying it in the percent-encoded form so a host that is blank or invisible once decoded still shows up in the message.
    case invalidHost(String)

    /// `invalidPort` is thrown when the input names a port outside `1...65535`, which `URL(string:)` itself accepts.
    case invalidPort(Int)

    var errorDescription: String? {
        switch self {
            case .empty:
                String(localized: "Please enter the address of your Nextcloud server.", comment: "Error shown when the server address field is empty.")

            case .tooLong:
                String(localized: "The address is too long. Please enter only the address of your Nextcloud server.", comment: "Error shown when the entered server address is longer than any address could reasonably be.")

            case .invalidCharacters:
                String(localized: "The address contains characters that are not allowed in a web address. Please check the address and try again.", comment: "Error shown when the entered server address contains control characters.")

            case let .unsupportedScheme(scheme):
                String(localized: "Cirruscope can only connect to a Nextcloud server over HTTP or HTTPS, not “\(scheme)”.", comment: "Error shown when the entered server address uses a scheme other than HTTP or HTTPS; the placeholder is that scheme.")

            case .credentialsInAddress:
                String(localized: "Please enter the server address without a user name or password. Signing in happens in the next step.", comment: "Error shown when the entered server address contains user information.")

            case let .malformed(address):
                String(localized: "“\(address)” is not a valid URL. Please check the address and try again.", comment: "Alert message shown when the entered server address is not a valid URL; the placeholder is the address the user typed.")

            case .missingHost:
                String(localized: "The address is missing a server name. Please enter an address such as https://cloud.example.com.", comment: "Error shown when the entered server address names no server.")

            case let .invalidHost(host):
                String(localized: "“\(host)” is not a valid server name. Please check the address and try again.", comment: "Error shown when the server name in the entered address cannot name a server; the placeholder is that name.")

            case let .invalidPort(port):
                String(localized: "“\(port)” is not a valid port number. Please enter a port between 1 and 65535.", comment: "Error shown when the port in the entered server address is out of range; the placeholder is that port.")
        }
    }
}
