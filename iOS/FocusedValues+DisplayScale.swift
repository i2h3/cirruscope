// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

///
/// This extension carries the display scale of the window in front to the commands of an iPad's menu bar.
///
extension FocusedValues {
    ///
    /// How many pixels the screen of the window in front draws to the point, or `nil` while no window in front has said.
    ///
    /// Commands sit beside the windows rather than in one, so the content of a command group is laid out with SwiftUI's default display scale of one whatever screen the menu appears on. A bitmap rendered at that scale is drawn at twice or three times its size and looks blurred, which is what the server-app icons in the View menu did until the window in front was asked instead.
    ///
    @Entry
    var displayScale: CGFloat?
}
