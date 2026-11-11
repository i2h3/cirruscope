// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `NavigationActionTarget` is the frame a navigation action WebKit asked a navigation delegate to decide would load into, as `NavigationTypeProbe` records it.
enum NavigationActionTarget: Equatable, Sendable {
    /// `mainFrame` is the frame of the page itself.
    case mainFrame

    /// `subFrame` is a frame embedded in the page.
    case subFrame

    /// `newWindow` is no frame at all, the action's `targetFrame` being `nil` because it asks for a new window.
    case newWindow
}
