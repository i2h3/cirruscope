// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

///
/// `CirruscopeWebView` is the web view of the storyboard "Web Window" scene, differing from a plain `WKWebView` only in the items its context menu offers.
///
/// A link's context menu leaves out "Open Link", which navigates the page the link is in, and "Download Linked File".
/// Safari and other browsers offer no "Open Link", so it conflicts with the muscle memory and conventions of users who know them, and a menu item downloading the linked file has no place in Cirruscope's interface.
/// Every context menu also leaves out "Back", "Forward" and "Reload", which would make the web view feel like a browser rather than an app, and which the View menu still offers.
/// User feedback asked for all of them to be gone.
/// Everything else the menu holds stays exactly as WebKit builds it, which is why this removes items from the finished menu instead of replacing the menu: on the Mac there is no delegate to customize it through, and `willOpenMenu(_:with:)` is where AppKit hands over the menu right before showing it.
///
final class CirruscopeWebView: WKWebView {
    /// `omittedItems` identify the items of WebKit's default menu that this web view leaves out: the one opening a link in the page it was clicked in, the one downloading the file a link points to, and the ones going back, going forward and reloading.
    ///
    /// WebKit gives each item of its default menu an identifier beginning with `WKMenuItemIdentifier`, and no public header declares them, so they are matched as literals.
    /// A release that renames one would merely bring its item back, since an item nothing matches is left in the menu.
    private static let omittedItems: Set<NSUserInterfaceItemIdentifier> = [
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLink"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierDownloadLinkedFile"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierGoBack"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierGoForward"),
        NSUserInterfaceItemIdentifier("WKMenuItemIdentifierReload"),
    ]

    /// `logger` records which items a context menu lost.
    private let logger = Logger(for: CirruscopeWebView.self)

    ///
    /// `willOpenMenu(_:with:)` removes the omitted items from the menu AppKit is about to show for a right-click.
    ///
    /// A menu holding none of them passes through unchanged.
    /// One that held nothing else, as a click on an empty part of a page does, ends up empty, and AppKit shows no menu at all then.
    ///
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

    ///
    /// `removeStraySeparators(from:)` removes the separators a removed item left leading, trailing or next to another separator, which AppKit would draw as a stray line.
    ///
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
