// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `NavigationActionTarget` is the frame a navigation action WebKit asked a navigation delegate to decide would load into, as `NavigationTypeProbe` records it.
///
/// It is recorded because both apps decide the sign-out route only for some targets: the Mac app's navigation delegate only for the main frame, leaving a new-window request to its `WKUIDelegate`, and the iOS app's decider for the main frame and a new-window request alike.
///
enum NavigationActionTarget: Equatable, Sendable {
    ///
    /// `mainFrame` is the frame of the page itself.
    ///
    case mainFrame

    ///
    /// `subFrame` is a frame embedded in the page.
    ///
    case subFrame

    ///
    /// `newWindow` is no frame at all, the action's `targetFrame` being `nil` because it asks for a new window.
    ///
    case newWindow
}
