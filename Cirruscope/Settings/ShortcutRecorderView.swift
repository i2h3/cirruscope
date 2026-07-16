// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `ShortcutRecorderView` is a focusable, text-field-style control that records a single keyboard shortcut.
///
/// Clicking it makes it the first responder, which is the visual cue that it is recording; the next key combination the user presses becomes its value, provided it includes at least one of Command, Option, or Control, or is itself a function-region key (F-keys, arrows, Home/End, Page Up/Down, etc.) that can safely be recorded bare. A trailing clear button, shown only while a shortcut is assigned, removes the shortcut. `ServerAppsViewController` places one per row in its apps table and observes `onChange` to persist the recorded `AppShortcutTransferObject`, or `nil` when the user clears it, via `AccountStore.setShortcut(_:forAppID:)`.
class ShortcutRecorderView: NSTableCellView {
    /// `shortcut` is the currently recorded shortcut, or `nil` when none is assigned.
    ///
    /// Setting it shows or hides the clear button and refreshes the displayed text; the user changes it by recording a new combination, pressing Delete while recording, or clicking the clear button.
    var shortcut: AppShortcutTransferObject? {
        didSet {
            clearButton.isHidden = shortcut == nil
            updateDisplay()
        }
    }

    /// `onChange` is invoked whenever the user records a new shortcut or clears the existing one.
    ///
    /// It is a `@MainActor` closure because it is only ever invoked from this main-actor control and `ServerAppsViewController` uses it to call the main-actor `AccountStore` synchronously.
    var onChange: (@MainActor (AppShortcutTransferObject?) -> Void)?

    /// `displayField` is the bezeled, non-editable text field that gives the control its text-field appearance and shows the placeholder, the recording prompt, or the recorded shortcut.
    private let displayField = NSTextField()

    /// `clearButton` is the trailing image-only button that clears the recorded shortcut, shown only while one is assigned.
    private let clearButton = NSButton()

    /// `logger` records this control's activity under the `ShortcutRecorderView` category.
    private let logger = Logger(for: ShortcutRecorderView.self)

    /// `isRecording` is `true` while the control is the first responder and waiting to capture the next key combination.
    private var isRecording = false {
        didSet {
            updateDisplay()
        }
    }

    /// `eventMonitor` is the local key-event monitor that is active only while recording.
    ///
    /// It is only ever assigned on the main actor while recording starts and stops, and read again in `deinit` once no other reference remains, so `nonisolated(unsafe)` lets the `nonisolated` deinit tear it down without a data race.
    private nonisolated(unsafe) var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func configure() {
        focusRingType = .default

        displayField.isEditable = false
        displayField.isSelectable = false
        displayField.isBezeled = false
        displayField.drawsBackground = false
        displayField.focusRingType = .none
        displayField.lineBreakMode = .byTruncatingTail
        displayField.alignment = .left
        displayField.font = .systemFont(ofSize: NSFont.systemFontSize)
        displayField.translatesAutoresizingMaskIntoConstraints = false

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.imagePosition = .imageOnly
        clearButton.isBordered = false
        clearButton.setButtonType(.momentaryChange)
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.refusesFirstResponder = true
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.isHidden = shortcut == nil
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(displayField)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            displayField.leadingAnchor.constraint(equalTo: leadingAnchor),
            displayField.trailingAnchor.constraint(equalTo: trailingAnchor),
            displayField.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateDisplay()
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)

        if clearButton.isHidden == false, clearButton.frame.contains(local) {
            return clearButton
        }

        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with _: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        startRecording()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func layout() {
        super.layout()
        noteFocusRingMaskChanged()
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill()
    }

    override var focusRingMaskBounds: NSRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateDisplay()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard eventMonitor == nil else {
            return
        }

        isRecording = true
        logger.debug("Started recording")

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: makeKeyDownHandler())
    }

    /// `makeKeyDownHandler()` builds the local event monitor handler `startRecording()` installs.
    ///
    /// It is `nonisolated` for the same reason as `ServerAddressViewController.makeAuthenticationCompletionHandler()`: `ShortcutRecorderView` is main-actor-isolated via `NSView`, so a closure written directly inside one of its methods would inherit that isolation too, even though its body only creates a `Task`. AppKit does not annotate `NSEvent.addLocalMonitorForEvents(matching:handler:)`'s handler as main-actor, so never assume the calling thread; the monitor's return value does not depend on `handle(_:)` completing first.
    ///
    /// Only the `Sendable` fields `handle(keyCode:modifierFlags:charactersIgnoringModifiers:)` needs cross into the `Task`, rather than `event` itself, since `NSEvent` is not `Sendable`.
    private nonisolated func makeKeyDownHandler() -> (NSEvent) -> NSEvent? {
        { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let charactersIgnoringModifiers = event.charactersIgnoringModifiers
            Task { @MainActor [weak self] in
                self?.handle(keyCode: keyCode, modifierFlags: modifierFlags, charactersIgnoringModifiers: charactersIgnoringModifiers)
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        logger.debug("Stopped recording")

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }

        eventMonitor = nil
    }

    /// `endRecording()` resigns first-responder status so recording stops and the focus ring disappears, called once a combination has been captured or recording has been cancelled.
    private func endRecording() {
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        } else {
            stopRecording()
        }
    }

    private func handle(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) {
        // Escape cancels recording without changing the shortcut.
        if keyCode == 53 {
            endRecording()
            return
        }

        // Delete or Forward Delete clears the shortcut.
        if keyCode == 51 || keyCode == 117 {
            endRecording()
            shortcut = nil
            onChange?(nil)
            return
        }

        let modifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])

        // AppKit sets `.function` on any keyDown whose key is in the function/special-key region (F-keys, arrows,
        // Home/End, Page Up/Down, etc.), regardless of whether the physical fn key is held.
        let isFunctionRegionKey = modifierFlags.contains(.function)

        // Require at least one of Command, Option, or Control so a bare shortcut cannot collide with plain typing —
        // unless the key is a function-region key, which never collides with typing and so may be recorded bare.
        guard isFunctionRegionKey || modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            return
        }

        guard let characters = charactersIgnoringModifiers, characters.isEmpty == false else {
            return
        }

        endRecording()

        let recorded = AppShortcutTransferObject(keyEquivalent: characters.lowercased(), modifierFlags: modifiers.rawValue)
        shortcut = recorded
        onChange?(recorded)
    }

    @objc
    private func clear() {
        shortcut = nil
        onChange?(nil)
        logger.debug("Cleared")
    }

    // MARK: - Display

    private func updateDisplay() {
        if isRecording {
            displayField.stringValue = "Press now"
            displayField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .controlAccentColor
            logger.debug("Updated display for recording")
        } else if let shortcut {
            displayField.stringValue = Self.displayString(for: shortcut)
            displayField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
            logger.debug("Updated display for shortcut presentation")
        } else {
            displayField.stringValue = "None"
            displayField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
            logger.debug("Updated display for empty presentation")
        }
    }

    /// `functionRegionKeyNames` maps the Unicode Private Use Area scalars AppKit reserves for function-region keys
    /// (e.g. `NSF4FunctionKey` at U+F707, `NSHomeFunctionKey` at U+F729) to a friendly name for `displayString(for:)`.
    ///
    /// `AppShortcutTransferObject.keyEquivalent` stores these scalars unchanged for such keys, since that raw value is what
    /// `NSMenuItem.keyEquivalent` needs; this mapping only affects what is displayed, never what is stored.
    private static let functionRegionKeyNames: [Unicode.Scalar: String] = [
        Unicode.Scalar(0xF700)!: "↑",
        Unicode.Scalar(0xF701)!: "↓",
        Unicode.Scalar(0xF702)!: "←",
        Unicode.Scalar(0xF703)!: "→",
        Unicode.Scalar(0xF704)!: "F1",
        Unicode.Scalar(0xF705)!: "F2",
        Unicode.Scalar(0xF706)!: "F3",
        Unicode.Scalar(0xF707)!: "F4",
        Unicode.Scalar(0xF708)!: "F5",
        Unicode.Scalar(0xF709)!: "F6",
        Unicode.Scalar(0xF70A)!: "F7",
        Unicode.Scalar(0xF70B)!: "F8",
        Unicode.Scalar(0xF70C)!: "F9",
        Unicode.Scalar(0xF70D)!: "F10",
        Unicode.Scalar(0xF70E)!: "F11",
        Unicode.Scalar(0xF70F)!: "F12",
        Unicode.Scalar(0xF710)!: "F13",
        Unicode.Scalar(0xF711)!: "F14",
        Unicode.Scalar(0xF712)!: "F15",
        Unicode.Scalar(0xF713)!: "F16",
        Unicode.Scalar(0xF714)!: "F17",
        Unicode.Scalar(0xF715)!: "F18",
        Unicode.Scalar(0xF716)!: "F19",
        Unicode.Scalar(0xF717)!: "F20",
        Unicode.Scalar(0xF729)!: "Home",
        Unicode.Scalar(0xF72B)!: "End",
        Unicode.Scalar(0xF72C)!: "Page Up",
        Unicode.Scalar(0xF72D)!: "Page Down",
    ]

    /// `displayString(for:)` renders a shortcut as its symbolic representation, e.g. `⌃⌥⇧⌘F`.
    static func displayString(for shortcut: AppShortcutTransferObject) -> String {
        let flags = shortcut.modifierMask
        var result = ""

        if flags.contains(.control) {
            result += "⌃"
        }

        if flags.contains(.option) {
            result += "⌥"
        }

        if flags.contains(.shift) {
            result += "⇧"
        }

        if flags.contains(.command) {
            result += "⌘"
        }

        // Function-region keys are stored as an unreadable Private Use Area scalar (see `functionRegionKeyNames`),
        // so substitute a friendly name for display; every other key equivalent still just displays uppercased.
        if shortcut.keyEquivalent.unicodeScalars.count == 1,
           let scalar = shortcut.keyEquivalent.unicodeScalars.first,
           let name = functionRegionKeyNames[scalar]
        {
            result += name
        } else {
            result += shortcut.keyEquivalent.uppercased()
        }

        return result
    }
}
