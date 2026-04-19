import AppKit
import SwiftUI

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

        // statusBar level (25) + .fullScreenAuxiliary collection behavior
        // keeps the panel above fullscreen apps AND allows drag-and-drop.
        // NotchNook uses the same approach. screenSaverWindow (1000) blocks
        // inter-app drag routing and is unnecessarily high.
        level = .statusBar

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    // canBecomeKey must be true for WindowServer to route inter-app drag
    // sessions to this window. Focus theft is still prevented by the
    // .nonactivatingPanel style mask, which stops the panel from activating.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Wrapper view that hosts SwiftUI content without using constraints.
/// Prevents the _postWindowNeedsUpdateConstraints crash by keeping the
/// hosting view as a subview with manual frame management.
final class StableHostingWrapper: NSView {
    private var hostingView: NSView?

    func embed<V: View>(_ rootView: V) {
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        hostingView = hosting
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostingView?.frame = bounds
    }

    // Pass scroll events through to the hosting view
    override func scrollWheel(with event: NSEvent) {
        hostingView?.scrollWheel(with: event)
    }

    override class var requiresConstraintBasedLayout: Bool { false }
    override func updateConstraints() { super.updateConstraints() }
}
