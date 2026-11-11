// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import UserNotifications
import WebKit

/// `UserNotifier` posts the notifications only the Mac posts — those the Nextcloud web interface raises and those announcing a finished download — and answers a click on either.
@MainActor
final class UserNotifier {
    /// `shared` is the process-wide notifier instance, which remembers the web view behind each web notification for the app's lifetime.
    static let shared = UserNotifier()

    /// `logger` records notification activity under the `UserNotifier` category.
    let logger = Logger(for: UserNotifier.self)

    /// `webViewsByIdentifier` maps a posted notification's request identifier to the web view that created it, held weakly so closed windows are released, so that a click can be routed back to the originating page.
    private let webViewsByIdentifier = NSMapTable<NSString, WKWebView>.strongToWeakObjects()

    /// `webNotificationIDKey` is the `userInfo` key under which `post(title:body:tag:webNotificationID:webView:)` stores the page-side id the activation hook uses to find the original `Notification`.
    private static let webNotificationIDKey = "webNotificationID"

    /// `downloadFilePathKey` is the `userInfo` key under which `postDownloadFinished(filename:fileURL:)` stores a finished download's file path so a click can reveal it in Finder.
    private static let downloadFilePathKey = "downloadFilePath"

    /// `webNotificationIdentifierPrefix` is what the request identifier of a web notification posted under a tag starts with.
    ///
    /// The tag is chosen by the page, and posted as it stands it could spell a server notification's identifier, which would then be withdrawn, replaced or opened as the server's own; the prefix keeps the two namespaces apart.
    private static let webNotificationIdentifierPrefix = "web-notification-"

    /// `post(title:body:tag:webNotificationID:webView:)` posts a notification with `title` and `body`, remembering `webView` and `webNotificationID` so a later click can be routed back to the page that created it.
    func post(title: String, body: String, tag: String, webNotificationID: String, webView: WKWebView) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [Self.webNotificationIDKey: webNotificationID]

        let identifier = tag.isEmpty ? UUID().uuidString : Self.webNotificationIdentifierPrefix + tag
        webViewsByIdentifier.setObject(webView, forKey: identifier as NSString)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// `postDownloadFinished(filename:fileURL:)` posts a notification announcing that `filename` finished downloading, remembering `fileURL` so a click reveals the file in Finder.
    func postDownloadFinished(filename: String, fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Download Finished", comment: "Title of the notification shown when a file download finishes.")
        content.body = filename
        content.userInfo = [Self.downloadFilePathKey: fileURL.path(percentEncoded: false)]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// `respond(toNotificationWithIdentifier:userInfo:)` answers a click on a notification this type posted: it reveals a finished download in Finder, or brings the originating web window forward and runs the page's click handler for a web notification.
    func respond(toNotificationWithIdentifier identifier: String, userInfo: [String: String]) {
        guard let downloadFilePath = userInfo[Self.downloadFilePathKey] else {
            activate(identifier: identifier, webNotificationID: userInfo[Self.webNotificationIDKey])
            return
        }

        revealDownloadedFile(atPath: downloadFilePath)
    }

    /// `activate(identifier:webNotificationID:)` brings the app and the originating web window forward and runs that page's click handler for the notification, navigating the web interface to the notification's target.
    ///
    /// If the originating window has since closed, it activates the app and does nothing further, since the page that knew the notification's target is gone.
    private func activate(identifier: String, webNotificationID: String?) {
        NSApp.activate()

        guard let webView = webViewsByIdentifier.object(forKey: identifier as NSString) else {
            return
        }

        webView.window?.makeKeyAndOrderFront(nil)

        if let webNotificationID {
            webView.evaluateJavaScript("window.Cirruscope?.activateNotification?.(\"\(webNotificationID)\")")
        }
    }

    /// `revealDownloadedFile(atPath:)` brings the app forward and opens Finder with the finished download selected.
    private func revealDownloadedFile(atPath path: String) {
        NSApp.activate()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
