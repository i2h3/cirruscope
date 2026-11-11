// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `AccentColorMonitor` watches the two system inputs that can change the accent color Cirruscope forwards into its web views — the accent-color preference itself and the light/dark appearance — and posts `Notification.Name.accentColorDidChange` so every open `WebViewController` re-resolves and re-applies its own value.
@MainActor
final class AccentColorMonitor: NSObject {
    /// `shared` is the process-wide monitor, retained for the app's lifetime so a single object owns the two system observations.
    static let shared = AccentColorMonitor()

    /// `logger` records accent-color and appearance change activity under the `AccentColorMonitor` category; it is `nonisolated` so the `nonisolated` observers can log through it.
    nonisolated let logger = Logger(for: AccentColorMonitor.self)

    /// `appearanceObservation` retains the key-value observation of `NSApplication.effectiveAppearance` that reports light/dark switches, whether the user flips the setting in System Settings or macOS switches automatically at sunset.
    private var appearanceObservation: NSKeyValueObservation?

    /// `start()` installs both system observations: the key-value observation of `NSApplication.effectiveAppearance` for light/dark switches, and the `NSColor.systemColorsDidChangeNotification` observer for accent- and highlight-color changes.
    func start() {
        guard appearanceObservation == nil else {
            return
        }

        logger.info("Starting accent color monitor")
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [], changeHandler: makeEffectiveAppearanceChangeHandler())
        NotificationCenter.default.addObserver(self, selector: #selector(systemColorsDidChange), name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    /// `makeEffectiveAppearanceChangeHandler()` builds the key-value observation change handler `start()` registers on `NSApplication.effectiveAppearance`.
    private nonisolated func makeEffectiveAppearanceChangeHandler() -> @Sendable (NSApplication, NSKeyValueObservedChange<NSAppearance>) -> Void {
        { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Effective appearance changed; announcing accent color change")
                announceAccentColorChange()
            }
        }
    }

    /// `systemColorsDidChange()` handles `NSColor.systemColorsDidChangeNotification`, which AppKit posts once it has invalidated its own color caches.
    @objc
    private nonisolated func systemColorsDidChange() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            logger.debug("System colors changed; announcing accent color change")
            announceAccentColorChange()
        }
    }

    /// `announceAccentColorChange()` posts `Notification.Name.accentColorDidChange` so every open `WebViewController` re-applies the appearance to its live web view.
    private func announceAccentColorChange() {
        NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
    }
}
