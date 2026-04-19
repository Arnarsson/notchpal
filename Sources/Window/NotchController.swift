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
    var showHistory = false
    var focusedIndex: Int = -1

    var selectedAgent: AgentStatus?

    private var panel: NotchPanel?
    private var animating = false
    private var hotkeyRef: EventHotKeyRef?
    private var keyMonitor: Any?

    // MARK: - Lifecycle

    func show() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }

        let panel = NotchPanel()
        let hosting = NSHostingView(rootView: NotchRootView(controller: self))
        panel.contentView = hosting

        panel.setFrame(NotchGeometry.frame(for: .collapsed, on: screen), display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        registerHotkey()
        installKeyboardNav()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        unregisterHotkey()
        removeKeyboardNav()
    }

    // MARK: - Intents

    func hoverBegan() {
        state = .expanded
    }

    func hoverEnded() {
        // Don't collapse during animation — prevents the expand/collapse race
        // that triggers the constraint crash.
        guard !animating else { return }
        selectedAgent = nil
        showDropSuggestions = false
        showHistory = false
        focusedIndex = -1
        state = .collapsed
    }

    func toggle() {
        if state == .expanded {
            selectedAgent = nil
            showDropSuggestions = false
            showHistory = false
            focusedIndex = -1
            state = .collapsed
        } else {
            state = .expanded
        }
    }

    func toggleHistory() {
        showHistory.toggle()
    }

    func selectAgent(_ agent: AgentStatus) {
        selectedAgent = agent
    }

    func deselectAgent() {
        selectedAgent = nil
    }

    func resizePanel() { /* no-op: fixed size */ }

    func didReceiveDrop(_ url: URL) {
        lastDroppedFile = url
        showDropSuggestions = true
        AgentRegistry.shared.suggestForDrop(url)
        state = .expanded
    }

    func dismissDropSuggestions() {
        showDropSuggestions = false
        AgentRegistry.shared.clearDropSuggestions()
    }

    // MARK: - Global hotkey (⌘Space)

    private func registerHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4E504C)
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            Task { @MainActor in
                NotchController.hotkeyFired()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    private static func hotkeyFired() {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let controller = delegate.notchController else { return }
        controller.toggle()
    }

    // MARK: - Keyboard navigation

    private func installKeyboardNav() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.state == .expanded else { return event }
            let agents = AgentRegistry.shared.agents
            switch event.keyCode {
            case 125: // down
                self.focusedIndex = min(self.focusedIndex + 1, agents.count - 1)
                return nil
            case 126: // up
                self.focusedIndex = max(self.focusedIndex - 1, -1)
                return nil
            case 36: // enter
                if self.selectedAgent != nil { return event }
                if self.focusedIndex >= 0, self.focusedIndex < agents.count {
                    self.selectAgent(agents[self.focusedIndex])
                }
                return nil
            case 53: // escape
                if self.selectedAgent != nil {
                    self.deselectAgent()
                } else if self.showHistory {
                    self.showHistory = false
                } else {
                    self.toggle()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardNav() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Animation

    private func animatePanelFrame(to state: NotchState) {
        guard let panel, let screen = NSScreen.main else { return }

        let target = NotchGeometry.frame(for: state, on: screen)
        let expanding = (state == .expanded)

        animating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = expanding ? 0.35 : 0.2
            ctx.timingFunction = CAMediaTimingFunction(
                name: expanding ? .easeInEaseOut : .easeIn
            )
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.animating = false
        })
    }
}
