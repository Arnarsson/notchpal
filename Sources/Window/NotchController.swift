import AppKit
import SwiftUI

@Observable
final class NotchController {

    var state: NotchState = .collapsed {
        didSet {
            guard oldValue != state else { return }
            animatePanelFrame(to: state)
        }
    }

    var lastDroppedFile: URL?

    var selectedAgent: AgentStatus? {
        didSet { resizeForContent() }
    }

    private var panel: NotchPanel?
    private var animating = false

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }

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

    // MARK: - Intents

    func hoverBegan() {
        state = .expanded
    }

    func hoverEnded() {
        guard !animating else { return }
        selectedAgent = nil
        state = .collapsed
    }

    func selectAgent(_ agent: AgentStatus) {
        selectedAgent = agent
    }

    func deselectAgent() {
        selectedAgent = nil
    }

    func didReceiveDrop(_ url: URL) {
        lastDroppedFile = url
        state = .expanded
    }

    // MARK: - Dynamic sizing

    private func resizeForContent() {
        guard state == .expanded else { return }
        guard let panel, let screen = NSScreen.main else { return }

        let size: CGSize
        if let agent = selectedAgent {
            size = NotchGeometry.detailSize(for: agent.id)
        } else {
            let registry = AgentRegistry.shared
            let active = registry.agents.filter { $0.state == .busy || $0.state == .attention || $0.state == .error }.count
            let passive = registry.agents.filter { $0.state == .idle || $0.state == .done }.count
            size = NotchGeometry.listSize(activeCount: active, passiveCount: passive)
        }

        let target = NotchGeometry.frame(size: size, on: screen)
        animating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.animating = false
        })
    }

    // MARK: - Animation

    private func animatePanelFrame(to state: NotchState) {
        guard let panel, let screen = NSScreen.main else { return }

        let target: NSRect
        if state == .expanded {
            let registry = AgentRegistry.shared
            let active = registry.agents.filter { $0.state == .busy || $0.state == .attention || $0.state == .error }.count
            let passive = registry.agents.filter { $0.state == .idle || $0.state == .done }.count
            let size = NotchGeometry.listSize(activeCount: active, passiveCount: passive)
            target = NotchGeometry.frame(size: size, on: screen)
        } else {
            target = NotchGeometry.frame(for: .collapsed, on: screen)
        }

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
