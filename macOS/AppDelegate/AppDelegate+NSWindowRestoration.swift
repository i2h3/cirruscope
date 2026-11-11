// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `AppDelegate`'s conformance to `NSWindowRestoration` recreates the web windows AppKit saved at quit, so a relaunch reopens the same pages at the same frames.
extension AppDelegate: NSWindowRestoration {
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder, completionHandler: @escaping (NSWindow?, (any Error)?) -> Void) {
        // AppKit calls this on the main thread during launch; bridge to the main-actor-isolated delegate to recreate the window.
        MainActor.assumeIsolated {
            let window = (NSApp.delegate as? AppDelegate)?.restoreWebWindow(identifier: identifier, state: state)
            completionHandler(window, nil)
        }
    }

    /// `restoreWebWindow(identifier:state:)` rebuilds a web window AppKit is restoring, pointed at the page saved in `state`, or returns `nil` when no credentials are stored so a logged-out relaunch restores no orphaned windows.
    private func restoreWebWindow(identifier: NSUserInterfaceItemIdentifier, state: NSCoder) -> NSWindow? {
        guard let serverAddress = AccountStore.shared.serverAddress, Keychain.credentials(for: serverAddress) != nil else {
            return nil
        }

        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? WebWindowController else {
            return nil
        }

        windowController.targetURL = state.decodeObject(of: NSURL.self, forKey: WebWindow.restorableStateURLKey) as URL?
        windowController.window?.identifier = identifier
        track(windowController)

        return windowController.window
    }
}
