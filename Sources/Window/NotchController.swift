import AppKit
import SwiftUI
import Carbon.HIToolbox

@Observable
final class NotchController {

    var state: NotchState = .collapsed {
        didSet {
            guard oldValue != state else { return }
            animatePanelFrame(to: state)
        }
    }

    var lastDroppedFile: URL?
    var showDropSuggestions = false

    var selectedAgent: AgentStatus? {
        didSet { resizeForContent() }
    }

    private var panel: NotchPanel?
    private var animating = false
    private var hotkeyRef: EventHotKeyRef?

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

        registerHotkey()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        unregisterHotkey()
    }

    // MARK: - Intents

    func hoverBegan() {
        state = .expanded
    }

    func hoverEnded() {
        guard !animating else { return }
        selectedAgent = nil
        showDropSuggestions = false
        state = .collapsed
    }

    func toggle() {
        if state == .expanded {
            selectedAgent = nil
            showDropSuggestions = false
            state = .collapsed
        } else {
            state = .expanded
        }
    }

    func selectAgent(_ agent: AgentStatus) {
        selectedAgent = agent
    }

    func deselectAgent() {
        selectedAgent = nil
    }

    func didReceiveDrop(_ url: URL) {
        lastDroppedFile = url
        showDropSuggestions = true
        AgentRegistry.shared.suggestForDrop(url)
        state = .expanded
        resizeForContent()
    }

    func dismissDropSuggestions() {
        showDropSuggestions = false
        AgentRegistry.shared.clearDropSuggestions()
        resizeForContent()
    }

    // MARK: - Global hotkey (⌘Space)

    private func registerHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4E504C)  // "NPL"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            Task { @MainActor in
                NotchController.hotkeyFired()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // ⌘Space = kVK_Space + cmdKey
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    private static func hotkeyFired() {
        // Find the controller through the app delegate
        guard let delegate = NSApp.delegate as? AppDelegate,
              let controller = delegate.notchController else { return }
        controller.toggle()
    }

    // MARK: - Dynamic sizing

    private func resizeForContent() {
        guard state == .expanded else { return }
        guard let panel, let screen = NSScreen.main else { return }

        let size: CGSize
        if let agent = selectedAgent {
            size = NotchGeometry.detailSize(for: agent.id)
        } else if showDropSuggestions {
            size = CGSize(width: 560, height: 180)
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
            if showDropSuggestions {
                target = NotchGeometry.frame(size: CGSize(width: 560, height: 180), on: screen)
            } else {
                let registry = AgentRegistry.shared
                let active = registry.agents.filter { $0.state == .busy || $0.state == .attention || $0.state == .error }.count
                let passive = registry.agents.filter { $0.state == .idle || $0.state == .done }.count
                let size = NotchGeometry.listSize(activeCount: active, passiveCount: passive)
                target = NotchGeometry.frame(size: size, on: screen)
            }
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
