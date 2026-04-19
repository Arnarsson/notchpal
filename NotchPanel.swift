import AppKit

/// The floating panel that hosts the notch UI.
///
/// Critical choices:
/// - `.nonactivatingPanel` style: never steals focus from the active app.
/// - `.borderless` style: we draw the chrome ourselves (rounded bottom corners).
/// - `screenSaverWindow` level: sits above fullscreen apps. `.statusBar` is not high enough.
/// - `.fullScreenAuxiliary` collection behavior: panel continues to render when another
///   app enters fullscreen on the same display.
/// - `.canJoinAllSpaces`: follows the user across Spaces; no per-Space flicker.
final class NotchPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true

        // The crucial bit: sit above fullscreen apps.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    // Non-activating panels must explicitly opt out of becoming key/main
    // to guarantee no focus theft. `.nonactivatingPanel` mostly covers this,
    // but we belt-and-braces it here.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
