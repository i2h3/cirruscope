// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

/// This extension turns the bitmap `ServerAppIcons` renders into the template image AppKit's menus and table cells take.
extension NSImage {
    /// `serverAppIconSize` is the edge length, in points, that a server app's icon is drawn at in a menu.
    ///
    /// AppKit grows a menu row to fit an image taller than the text beside it, so an icon much above this makes the whole list taller than the rest of the menu it sits in. Sixteen points is what the system's own imaged menu items use.
    static let serverAppIconSize: CGFloat = 16

    /// `serverAppIcon(forAppID:serverAddress:size:)` is the icon of one Nextcloud app, ready to be handed to a menu item, or `nil` if none has been cached for it yet.
    static func serverAppIcon(forAppID appID: String, serverAddress: URL, size: CGFloat = NSImage.serverAppIconSize) -> NSImage? {
        let bounds = CGSize(width: size, height: size)

        guard let image = ServerAppIcons.shared.image(forAppID: appID, serverAddress: serverAddress, size: bounds, scale: 2) else {
            return nil
        }

        let icon = NSImage(cgImage: image, size: NSSize(width: size, height: size))
        icon.isTemplate = true

        return icon
    }
}
