// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import UserNotifications
import WebKit

/// `UserNotifier` bridges notifications created by the Nextcloud web interface into the macOS Notification Center and makes them actionable.
///
/// `WebViewController` forwards each web `Notification` through its `notification` script-message handler to `post(title:body:tag:webNotificationID:webView:)`, which posts a `UNNotificationRequest`. `AppDelegate` calls `configure()` on launch to register this object as the `UNUserNotificationCenter` delegate, and `WebViewController` calls `requestAuthorization()` when a web window opens.
/// When the user clicks a notification, `userNotificationCenter(_:didReceive:withCompletionHandler:)` brings the originating web window forward and asks its page to run the notification's own click handler, so the web interface navigates to the notification's target as it would natively.
final class UserNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// `shared` is the process-wide notifier instance, used so a single object owns the `UNUserNotificationCenter` delegate relationship for the app's lifetime.
    static let shared = UserNotifier()

    /// `logger` records notification activity under the `UserNotifier` category; it is `nonisolated` so the `nonisolated` `UNUserNotificationCenterDelegate` callbacks can log through it.
    nonisolated let logger = Logger(for: UserNotifier.self)

    /// `webViewsByIdentifier` maps a posted notification's request identifier to the web view that created it, held weakly so closed windows are released, so that a click can be routed back to the originating page.
    private let webViewsByIdentifier = NSMapTable<NSString, WKWebView>.strongToWeakObjects()

    /// `downloadFilePathKey` is the `userInfo` key under which `postDownloadFinished(filename:fileURL:)` stores a finished download's file path so a click can reveal it in Finder.
    ///
    /// It is `nonisolated` so the `nonisolated` delegate callback that inspects a clicked notification can read it.
    private nonisolated static let downloadFilePathKey = "downloadFilePath"

    /// `configure()` registers `shared` as the `UNUserNotificationCenter` delegate so notifications are presented even while Cirruscope is the active app and so clicks are delivered here.
    ///
    /// `AppDelegate.applicationDidFinishLaunching(_:)` calls it once, before the launch sequence completes, as `UNUserNotificationCenter` requires its delegate to be set by then.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// `requestAuthorization()` asks the user for permission to show alerts and play sounds, prompting only the first time the authorization state is undetermined.
    ///
    /// `WebViewController` calls it when a web window opens so the prompt appears in the context of a connected server rather than at launch.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
            } else if granted == false {
                logger.notice("Notification authorization was denied")
            }
        }
    }

    /// `post(title:body:tag:webNotificationID:webView:)` posts a notification with `title` and `body`, remembering `webView` and `webNotificationID` so a later click can be routed back to the page that created it.
    ///
    /// When `tag` is non-empty it is used as the request identifier so a web notification reusing a tag replaces the earlier one, matching the web Notification API; otherwise a fresh identifier is generated. `webNotificationID` is the page-side id the activation hook uses to find the original `Notification`.
    func post(title: String, body: String, tag: String, webNotificationID: String, webView: WKWebView) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["webNotificationID": webNotificationID]

        let identifier = tag.isEmpty ? UUID().uuidString : tag
        webViewsByIdentifier.setObject(webView, forKey: identifier as NSString)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// `postDownloadFinished(filename:fileURL:)` posts a notification announcing that `filename` finished downloading, remembering `fileURL` so a click reveals the file in Finder.
    ///
    /// `DownloadManager` calls it from `downloadDidFinish(_:)`. It reuses the authorization already requested when a web window opened, and its `userInfo` carries the file path under `downloadFilePathKey` so `userNotificationCenter(_:didReceive:withCompletionHandler:)` can distinguish it from a web notification.
    func postDownloadFinished(filename: String, fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Download Finished", comment: "Title of the notification shown when a file download finishes.")
        content.body = filename
        content.userInfo = [Self.downloadFilePathKey: fileURL.path]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        let webNotificationID = userInfo["webNotificationID"] as? String
        let downloadFilePath = userInfo[Self.downloadFilePathKey] as? String

        Task { @MainActor in
            if let downloadFilePath {
                self.revealDownloadedFile(atPath: downloadFilePath)
            } else {
                self.activate(identifier: identifier, webNotificationID: webNotificationID)
            }
        }

        completionHandler()
    }

    /// `activate(identifier:webNotificationID:)` brings the app and the originating web window forward and runs that page's click handler for the notification, navigating the web interface to the notification's target.
    ///
    /// If the originating window has since closed, it activates the app and does nothing further, since the page that knew the notification's target is gone.
    @MainActor
    private func activate(identifier: String, webNotificationID: String?) {
        NSApp.activate(ignoringOtherApps: true)

        guard let webView = webViewsByIdentifier.object(forKey: identifier as NSString) else {
            return
        }

        webView.window?.makeKeyAndOrderFront(nil)

        if let webNotificationID {
            webView.evaluateJavaScript("window.__cirruscopeActivateNotification && window.__cirruscopeActivateNotification(\"\(webNotificationID)\")")
        }
    }

    /// `revealDownloadedFile(atPath:)` brings the app forward and opens Finder with the finished download selected.
    ///
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)` calls it when the clicked notification was posted by `postDownloadFinished(filename:fileURL:)`.
    @MainActor
    private func revealDownloadedFile(atPath path: String) {
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
