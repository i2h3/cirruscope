// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ConversationWebRoute` is where a Nextcloud Talk conversation lives in the web interface.
enum ConversationWebRoute {
    /// `appID` is the identifier of the Nextcloud app that owns a conversation, which is what its icon is cached under.
    static let appID = "spreed"

    /// `url(forToken:on:)` is the address of the conversation `token` names on `serverAddress`, or `nil` when there is no address to be confident in.
    static func url(forToken token: String, on serverAddress: URL) -> SameOriginURL? {
        SameOriginURL(components: ["call", token], relativeTo: serverAddress)
    }
}
