import AppKit

/// `WebWindow` is the window of the storyboard "Web Window" scene that hosts `WebViewController`.
///
/// It keeps the standard close, miniaturize, and zoom buttons aligned with Framecloud's custom title bar. AppKit returns those buttons to their default position on every layout pass, so `WebWindow` repositions them again at the end of the same pass — synchronously, so they are never displayed at the default position and do not visibly jump.
class WebWindow: NSWindow {

    /// `toolbarHeight` is the height of Framecloud's custom title bar that the window buttons are vertically centered within.
    private static let toolbarHeight: CGFloat = 50

    /// `leadingInset` is the distance from the window's leading edge to the first window button.
    private static let leadingInset: CGFloat = 20

    /// `buttonSpacing` is the horizontal distance between the leading edges of adjacent window buttons.
    private static let buttonSpacing: CGFloat = 23

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        repositionControlButtons()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        repositionControlButtons()
    }

    /// `repositionControlButtons()` moves the close, miniaturize, and zoom buttons to align with the custom title bar, leaving them untouched while they are not yet available or while the window is in fullscreen.
    ///
    /// In fullscreen macOS relocates the window buttons into the auto-revealing title bar; the custom placement is skipped there so the buttons stay reachable in that title bar (including the green button used to leave fullscreen) instead of being pulled into the hidden content area.
    private func repositionControlButtons() {
        guard styleMask.contains(.fullScreen) == false else {
            return
        }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for (index, type) in buttonTypes.enumerated() {
            guard let button = standardWindowButton(type),
                  let superview = button.superview
            else {
                continue
            }

            let buttonHeight = button.bounds.height
            let topInset = (Self.toolbarHeight - buttonHeight) / 2
            let leading = Self.leadingInset + CGFloat(index) * Self.buttonSpacing

            let originInWindow = NSPoint(x: leading, y: frame.height - topInset - buttonHeight)

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }
}
