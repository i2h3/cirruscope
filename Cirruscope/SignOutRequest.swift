// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WebKit

/// `SignOutRequest` is what a navigation to the connected server's sign-out route asks of the app, judged by how the navigation began.
enum SignOutRequest: Equatable {
    /// `explicit` means the user activated a link to the sign-out route, so the account is to be signed out of the app and its app password revoked.
    case explicit

    /// `scripted` means the navigation began some other way, typically the page's own script, so it is to be cancelled and the account kept.
    case scripted

    /// `of(_:)` is what a navigation to the sign-out route of type `navigationType` asks of the app.
    static func of(_ navigationType: WKNavigationType) -> SignOutRequest {
        switch navigationType {
            case .linkActivated:
                .explicit

            case .formSubmitted, .backForward, .reload, .formResubmitted, .other:
                .scripted

            @unknown default:
                .scripted
        }
    }
}
