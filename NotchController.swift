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

        // Initial frame at collapsed state.
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.1 : 0.35
            ctx.timingFunction = CAMediaTimingFunction(
                name: reduceMotion ? .easeOut : .easeInEaseOut
            )
            panel.animator().setFrame(target, display: true)
        }
    }
}
