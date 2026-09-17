// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension declares the in-process notifications only macOS posts and observes.
///
/// The two `AccountStore` posts are not here: the store is compiled into both apps, so its names live in `Cirruscope/NotificationName.swift` where both can see them.
extension Notification.Name {
    /// `downloadsDidChange` is posted by `DownloadManager` whenever its `downloads` list or a download's state changes so `DownloadViewController` can reload its table.
    static let downloadsDidChange = Notification.Name("DownloadsDidChange")

    /// `downloadDidStart` is posted by `DownloadManager` when a new transfer begins so `AppDelegate` can open and bring the Downloads window to the foreground.
    static let downloadDidStart = Notification.Name("DownloadDidStart")

    /// `unreadNotificationCountDidChange` is posted by `NotificationMonitor` whenever the unread server-notification count changes so other parts of the app can react without reaching into the monitor.
    static let unreadNotificationCountDidChange = Notification.Name("UnreadNotificationCountDidChange")

    /// `serverCredentialsRejected` is posted by `NotificationMonitor` when its event stream reports the stored app password was revoked so `AppDelegate` can clear the keychain and require a new sign-in.
    static let serverCredentialsRejected = Notification.Name("ServerCredentialsRejected")

    /// `accentColorDidChange` is posted by `AccentColorMonitor` whenever the macOS accent color or the light/dark appearance changes so every open `WebViewController` re-resolves the accent color for its own web view and forwards it into the page without a reload.
    ///
    /// It is the system-driven counterpart to `appearanceSettingsDidChange`, which carries the account's own appearance settings; both funnel into `WebViewController.reapplyAppearance()`.
    static let accentColorDidChange = Notification.Name("AccentColorDidChange")

    /// `nextcloudHeaderHeightDidChange` is posted by `NextcloudHeaderHeight` whenever a page reports a header height different from the one recorded so every open `WebWindowController` re-centers its window's standard window buttons in the new one.
    ///
    /// It is needed because a change in that height triggers no layout pass of its own, so a window would otherwise keep its old placement until it was next resized — and because the height reported by one page belongs to every open window, all of them showing the same server, rather than only to the one whose page reported it.
    static let nextcloudHeaderHeightDidChange = Notification.Name("NextcloudHeaderHeightDidChange")
}
