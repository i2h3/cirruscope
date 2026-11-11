// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Network

/// `ServerAddress` is a Nextcloud instance address the user typed or pasted, normalized into the one canonical form Cirruscope talks to a server with and shows back to them.
struct ServerAddress: Sendable {
    /// `url` is the canonical instance address, the value `ServerConnection.anonymous(address:)` is called with.
    let url: URL

    /// `inferredScheme` is `true` when the input carried no scheme of its own and HTTPS was supplied for it.
    let inferredScheme: Bool

    /// `displayString` is the canonical address as text, the value `ServerAddressFormatter` writes back into the server-address field.
    var displayString: String {
        url.absoluteString
    }

    /// `init(normalizing:)` turns raw user input into the canonical address, or throws the `ServerAddressError` explaining why the input cannot be one.
    init(normalizing input: String) throws(ServerAddressError) {
        let text = Self.sanitized(input)

        guard text.isEmpty == false else {
            throw .empty
        }

        guard text.count <= Self.maximumLength else {
            throw .tooLong
        }

        guard text.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) == false }) else {
            throw .invalidCharacters
        }

        let (candidate, inferredScheme) = try Self.schemed(text)

        guard let parsed = URL(string: candidate) else {
            throw .malformed(text)
        }

        guard let scheme = parsed.scheme?.lowercased(), Self.supportedSchemes.contains(scheme) else {
            throw .malformed(text)
        }

        guard parsed.user(percentEncoded: false) == nil else {
            throw .credentialsInAddress
        }

        guard parsed.password(percentEncoded: false) == nil else {
            throw .credentialsInAddress
        }

        guard var host = parsed.host(percentEncoded: false)?.lowercased() else {
            throw .missingHost
        }

        guard host.isEmpty == false else {
            throw .missingHost
        }

        if host.hasSuffix("."), host.count > 1 {
            host = String(host.dropLast())
        }

        guard Self.isResolvable(host: host) else {
            throw .invalidHost(parsed.host(percentEncoded: true) ?? host)
        }

        if host.contains(":") {
            host = "[" + host.replacingOccurrences(of: "%", with: "%25") + "]"
        }

        var port = ""

        if let number = parsed.port {
            guard number > 0, number <= 65535 else {
                throw .invalidPort(number)
            }

            if Self.defaultPorts[scheme] != number {
                port = ":" + String(number)
            }
        }

        let canonical = scheme + "://" + host + port + Self.instancePath(of: parsed.path(percentEncoded: true))

        guard let url = URL(string: canonical), url.absoluteString == canonical else {
            throw .malformed(text)
        }

        self.url = url
        self.inferredScheme = inferredScheme
    }

    /// `maximumLength` is the number of characters of input beyond which normalization refuses to look at the value at all.
    ///
    /// Nothing about a Nextcloud address needs anywhere near this much room; the limit exists so a pathological paste cannot be percent-encoded into a value that ends up in an alert message or a log line. The number itself is a judgement call rather than a standard.
    private static let maximumLength = 2048

    /// `supportedSchemes` are the two URL schemes Cirruscope can reach a Nextcloud server over, in the order the leading-scheme check tries them.
    private static let supportedSchemes = ["https", "http"]

    /// `defaultPorts` maps each supported scheme to the port it already implies, which the canonical form therefore omits.
    private static let defaultPorts = ["https": 443, "http": 80]

    /// `ignoredScalars` are the code points removed from the input outright before it is parsed.
    private static let ignoredScalars: Set<Unicode.Scalar> = ["\u{0009}", "\u{000A}", "\u{000D}", "\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}", "\u{2028}", "\u{2029}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2060}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{FEFF}"]

    /// `wrappingDelimiters` are the paired delimiters stripped from around an address that was copied together with the punctuation surrounding it.
    ///
    /// Angle brackets are the pair RFC 3986 itself recommends for delimiting a URL in running text, and mail clients add them; the quotation marks cover an address copied out of a document or a chat message, where the typographic pair is what an autocorrecting editor produced. Parentheses are deliberately absent, because a closing one can legitimately end a path.
    private static let wrappingDelimiters: [(Character, Character)] = [("<", ">"), ("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{00AB}", "\u{00BB}"), ("\u{2039}", "\u{203A}")]

    /// `entryPointSegments` are the first path segments that mark the start of a Nextcloud instance's own routing rather than part of the address of the instance itself.
    private static let entryPointSegments: Set<String> = ["apps", "avatar", "call", "core", "cron.php", "csrftoken", "f", "index.php", "login", "logout", "ocm-provider", "ocs", "ocs-provider", "public.php", "remote.php", "s", "settings", "status.php", "u"]

    /// `sanitized(_:)` removes the invisible and structural noise a paste carries, then trims the result and unwraps any delimiters left around it.
    ///
    /// Unwrapping repeats until nothing changes so that a doubly wrapped paste — a quoted angle-bracketed address — is reduced as well, and it trims again after each pass because the delimiters usually enclose spaces too.
    private static func sanitized(_ input: String) -> String {
        var value = String(String.UnicodeScalarView(input.unicodeScalars.filter { ignoredScalars.contains($0) == false })).trimmingCharacters(in: .whitespacesAndNewlines)
        var didUnwrap = true

        while didUnwrap {
            didUnwrap = false

            for (opening, closing) in wrappingDelimiters where value.count >= 2 && value.first == opening && value.last == closing {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                didUnwrap = true
            }
        }

        return value
    }

    /// `schemed(_:)` returns the input with a scheme it can be parsed as an absolute URL with, and whether that scheme had to be supplied, or throws when the input already carries one Cirruscope cannot use.
    private static func schemed(_ input: String) throws(ServerAddressError) -> (candidate: String, inferredScheme: Bool) {
        let lowercased = input.lowercased()

        for scheme in supportedSchemes where lowercased.hasPrefix(scheme + ":") {
            return (scheme + "://" + input.dropFirst(scheme.count + 1).drop { $0 == "/" }, false)
        }

        if input.hasPrefix("//") {
            return ("https:" + input, true)
        }

        let authority = input.prefix { $0 != "/" }

        if authority.filter({ $0 == ":" }).count >= 2, IPv6Address(String(authority)) != nil {
            return ("https://[" + authority.replacingOccurrences(of: "%", with: "%25") + "]" + input.dropFirst(authority.count), true)
        }

        if let colon = input.firstIndex(of: ":") {
            let token = input[input.startIndex ..< colon]
            let remainder = input[input.index(after: colon)...]

            if isSchemeToken(token) {
                if remainder.hasPrefix("//") {
                    throw .unsupportedScheme(token.lowercased())
                }

                if token.contains(".") == false, let first = remainder.first, isASCIIDigit(first) == false {
                    throw .unsupportedScheme(token.lowercased())
                }
            }
        }

        return ("https://" + input, true)
    }

    /// `isSchemeToken(_:)` answers whether `token` could be a URL scheme at all, per the RFC 3986 grammar: a letter followed by letters, digits, `+`, `-`, or `.`.
    private static func isSchemeToken(_ token: Substring) -> Bool {
        guard let first = token.first, first.isASCII, first.isLetter else {
            return false
        }

        return token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    /// `isASCIIDigit(_:)` answers whether `character` is one of `0` through `9`.
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// `isResolvable(host:)` answers whether `host` could name a server at all, `host` being the ASCII form `URL` has already converted an internationalized domain into.
    private static func isResolvable(host: String) -> Bool {
        if host.contains(":") {
            return IPv6Address(host) != nil
        }

        guard host.count <= 253 else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)

        guard labels.isEmpty == false else {
            return false
        }

        return labels.allSatisfy { label in
            label.isEmpty == false && label.count <= 63 && label.first != "-" && label.last != "-" && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// `instancePath(of:)` reduces a parsed path to the subpath the Nextcloud instance itself is installed under, as either the empty string or a path with no trailing slash.
    private static func instancePath(of path: String) -> String {
        var segments: [String] = []

        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            let lowercased = segment.lowercased()

            if entryPointSegments.contains(lowercased) {
                break
            }

            if lowercased == "." {
                continue
            }

            if lowercased == ".." {
                if segments.isEmpty == false {
                    segments.removeLast()
                }

                continue
            }

            segments.append(String(segment))
        }

        return segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
    }
}
