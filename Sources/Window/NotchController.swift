import AppKit
import SwiftUI

/// Owns the NotchPanel lifecycle and drives state transitions.
/// State is the single source of truth for collapsed vs expanded; SwiftUI reads it
/// through the environment, and the panel frame is animated in lockstep.
@Observable
final class NotchController {

    var state: NotchState = .collapsed {
        didSet {
            guard oldValue != state else { return }
            animatePanelFrame(to: state)
        }
    }

    /// The file most recently dropped onto the notch. In the spike, we just show it;
    /// post-spike this becomes the "give HEKLA context" pipeline.
    var lastDroppedFile: URL?

    private var panel: NotchPanel?
    private var animating = false

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else {
            // Main-screen-only is a hard constraint for the spike.
            return
        }

        let panel = NotchPanel()
        let hosting = NSHostingView(rootView: NotchRootView(controller: self))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting

        panel.setFrame(NotchGeometry.frame(for: .collapsed, on: screen), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Intents (called from SwiftUI / interaction layer)

    func hoverBegan() {
        state = .expanded
    }

    func hoverEnded() {
        // Don't collapse while a frame animation is in flight — the expanding
        // panel shifts the tracking area, which can falsely fire mouseExited.
        guard !animating else { return }
        state = .collapsed
    }

    func didReceiveDrop(_ url: URL) {
        lastDroppedFile = url
        state = .expanded
    }

    // MARK: - Animation

    private func animatePanelFrame(to state: NotchState) {
        guard let panel, let screen = NSScreen.main else { return }
        let target = NotchGeometry.frame(for: state, on: screen)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let expanding = (state == .expanded)
        let duration = reduceMotion ? 0.1 : (expanding ? 0.4 : 0.25)

        animating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = expanding
                ? CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
                : CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.animating = false
        })
    }
}
