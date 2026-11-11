// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `CirruscopeWebView` is the web view of the storyboard "Web Window" scene, differing from a plain `WKWebView` only in the items its context menu offers.
final class CirruscopeWebView: WKWebView {
    /// `omittedItems` identify the items of WebKit's default menu that this web view leaves out: the one opening a link in the page it was clicked in, the one downloading the file a link points to, and the ones going back, going forward and reloading.
    private static let omittedItems: Set<NSUserInterfaceItemIdentifier> = [
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLink"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadLinkedFile"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierGoBack"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierGoForward"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierReload"),
    ]

    /// `logger` records which items a context menu lost.
    private let logger = Logger(for: CirruscopeWebView.self)

    /// `willOpenMenu(_:with:)` removes the omitted items from the menu AppKit is about to show for a right-click.
    ///
    /// A menu holding none of them passes through unchanged.
    /// One that held nothing else, as a click on an empty part of a page does, ends up empty, and AppKit shows no menu at all then.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        let itemCount = menu.items.count

        for item in menu.items {
            guard let identifier = item.identifier, Self.omittedItems.contains(identifier) else {
                continue
            }

            menu.removeItem(item)
        }

        let removedCount = itemCount - menu.items.count

        if removedCount > 0 {
            removeStraySeparators(from: menu)
        }

        logger.debug("Context menu opened with \(itemCount) item(s); removed \(removedCount), \(menu.items.count) left")
    }

    /// `removeStraySeparators(from:)` removes the separators a removed item left leading, trailing or next to another separator, which AppKit would draw as a stray line.
    private func removeStraySeparators(from menu: NSMenu) {
        while let first = menu.items.first, first.isSeparatorItem {
            menu.removeItem(first)
        }

        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }

        for (previous, item) in zip(menu.items, menu.items.dropFirst()) where previous.isSeparatorItem && item.isSeparatorItem {
            menu.removeItem(item)
        }
    }
}
