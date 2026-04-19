import AppKit

/// The floating panel that hosts the notch UI.
/// Installs a guard that catches NSExceptions from constraint updates
/// instead of letting them crash the app.
final class NotchPanel: NSPanel {

    init() {
        Self.installExceptionGuard()
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

        level = .statusBar

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Exception guard

    /// Replaces _postWindowNeedsUpdateConstraints on NotchPanel with a
    /// version that catches the NSException instead of crashing.
    /// The original method is called inside a @try/@catch block.
    private static var guardInstalled = false

    private static func installExceptionGuard() {
        guard !guardInstalled else { return }
        guardInstalled = true

        let sel = NSSelectorFromString("_postWindowNeedsUpdateConstraints")
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, sel) else { return }
        let originalImp = method_getImplementation(originalMethod)

        typealias OriginalFunc = @convention(c) (AnyObject, Selector) -> Void
        let originalCall = unsafeBitCast(originalImp, to: OriginalFunc.self)

        let block: @convention(block) (AnyObject) -> Void = { obj in
            ObjCExceptionCatcher.catchException {
                originalCall(obj, sel)
            }
        }

        let newImp = imp_implementationWithBlock(block)
        class_addMethod(NotchPanel.self, sel, newImp, "v@:")
            || { class_replaceMethod(NotchPanel.self, sel, newImp, "v@:"); return true }()
    }
}
