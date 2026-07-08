import AppKit
import os

/// `ShortcutRecorderView` is a focusable, text-field-style control that records a single keyboard shortcut.
///
/// Clicking it makes it the first responder, which is the visual cue that it is recording; the next key combination the user presses (with at least one of Command, Option, or Control) becomes its value. A trailing clear button, shown only while a shortcut is assigned, removes the shortcut. `ServerAppsViewController` places one per row in its apps table and observes `onChange` to persist the recorded `KeyboardShortcut`, or `nil` when the user clears it, into `Settings.appShortcuts`.
class ShortcutRecorderView: NSView {
    /// `shortcut` is the currently recorded shortcut, or `nil` when none is assigned.
    ///
    /// Setting it shows or hides the clear button and refreshes the displayed text; the user changes it by recording a new combination, pressing Delete while recording, or clicking the clear button.
    var shortcut: KeyboardShortcut? {
        didSet {
            clearButton.isHidden = shortcut == nil
            updateDisplay()
        }
    }

    /// `onChange` is invoked whenever the user records a new shortcut or clears the existing one.
    var onChange: ((KeyboardShortcut?) -> Void)?

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
        displayField.drawsBackground = true
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
            displayField.topAnchor.constraint(equalTo: topAnchor),
            displayField.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    // MARK: - Recording

    private func startRecording() {
        guard eventMonitor == nil else {
            return
        }

        isRecording = true
        logger.debug("Started recording")

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
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

    private func handle(_ event: NSEvent) {
        // Escape cancels recording without changing the shortcut.
        if event.keyCode == 53 {
            endRecording()
            return
        }

        // Delete or Forward Delete clears the shortcut.
        if event.keyCode == 51 || event.keyCode == 117 {
            endRecording()
            shortcut = nil
            onChange?(nil)
            return
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])

        // Require at least one of Command, Option, or Control so the shortcut cannot collide with plain typing.
        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            return
        }

        guard let characters = event.charactersIgnoringModifiers, characters.isEmpty == false else {
            return
        }

        endRecording()

        let recorded = KeyboardShortcut(keyEquivalent: characters.lowercased(), modifierFlags: modifiers.rawValue)
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
            displayField.textColor = .controlAccentColor
            logger.debug("Updated display for recording")
        } else if let shortcut {
            displayField.stringValue = Self.displayString(for: shortcut)
            displayField.textColor = .labelColor
            logger.debug("Updated display for shortcut presentation")
        } else {
            displayField.stringValue = "None"
            displayField.textColor = .secondaryLabelColor
            logger.debug("Updated display for empty presentation")
        }
    }

    /// `displayString(for:)` renders a shortcut as its symbolic representation, e.g. `⌃⌥⇧⌘F`.
    static func displayString(for shortcut: KeyboardShortcut) -> String {
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

        result += shortcut.keyEquivalent.uppercased()

        return result
    }
}
