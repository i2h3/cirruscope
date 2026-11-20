// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// The Find command in an iPad menu bar's Edit menu, ⌘F: it presents the system find navigator over the page of the window in front. An iPhone has no menu bar, so there the command reaches only a hardware keyboard; the account menu's Find in Page item is the way in on the phone.
struct FindCommands: Commands {
    /// The find navigator state of the window in front, or `nil` while no window in front has one.
    @FocusedValue(FindNavigatorBridge.self)
    private var findNavigator

    var body: some Commands {
        // Into the Edit menu, which is where the Mac's storyboard puts its Find items too.
        CommandGroup(after: .textEditing) {
            Button("Find in Page") {
                findNavigator?.isPresented = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(findNavigator == nil)
        }
    }
}
