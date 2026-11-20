// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// Carries the system find navigator's visibility between a window's `NextcloudView` and the iPad menu bar's Find command: the view binds `findNavigator(isPresented:)` to `isPresented` and publishes this bridge as a focused scene value, and the command flips `isPresented` through that value, which reaches the window in front.
@Observable
@MainActor
final class FindNavigatorBridge {
    /// Whether the system find navigator is presented over the page.
    var isPresented = false
}
