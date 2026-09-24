// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NoteWebRoute` is where a note lives in the web interface.
///
/// Unlike a Talk conversation, a note sits under its app's own prefix — `/apps/notes/note/<id>` — so the path names its owner and `ServerAppTransferObject`'s resolution rule recognizes it as Notes without needing an entry in `ServerAppPath`'s table of root routes. The route's own requirement is that the identifier is digits, which is why the note's number addresses it and its title does not.
///
/// It is appended to the server address rather than written as a path from the root, for the reason `ConversationWebRoute` is: an address the *server* named already carries the instance's web root, and one the app builds does not. Read from the root against an instance served from `/nextcloud`, this would resolve onto the bare host and open something that has nothing to do with the account.
enum NoteWebRoute {
    /// `url(forID:on:)` is the address of the note `id` names on `serverAddress`, or `nil` when there is no address to be confident in.
    ///
    /// A negative identifier is refused rather than encoded. The server never issues one, so a negative value means something upstream is wrong, and `/apps/notes/note/-1` would be a request the server answers with its own error page — which looks to the user like the app opened the wrong note rather than like it declined to open one.
    static func url(forID id: Int, on serverAddress: URL) -> SameOriginURL? {
        guard id >= 0 else {
            return nil
        }

        let address = serverAddress
            .appending(path: "apps")
            .appending(path: "notes")
            .appending(path: "note")
            .appending(path: String(id))

        return SameOriginURL(path: address.absoluteString, relativeTo: serverAddress)
    }
}
