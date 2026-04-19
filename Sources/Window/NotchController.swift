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
    var focusedIndex: Int = -1  // -1 = no focus

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
        hosting.translatesAutoresizingMaskIntoConstraints = false
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

    func resizePanel() {
        // No-op: fixed expanded size, SwiftUI handles content layout
    }

    func didReceiveDrop(_ url: URL) {
        lastDroppedFile = url
        showDropSuggestions = true
        AgentRegistry.shared.suggestForDrop(url)
        state = .expanded
        // no-op: fixed expanded size
    }

    func dismissDropSuggestions() {
        showDropSuggestions = false
        AgentRegistry.shared.clearDropSuggestions()
        // no-op: fixed expanded size
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

    // MARK: - Keyboard navigation

    private func installKeyboardNav() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.state == .expanded else { return event }
            let agents = AgentRegistry.shared.agents
            switch event.keyCode {
            case 125: // down arrow
                self.focusedIndex = min(self.focusedIndex + 1, agents.count - 1)
                return nil
            case 126: // up arrow
                self.focusedIndex = max(self.focusedIndex - 1, -1)
                return nil
            case 36: // return/enter
                if self.selectedAgent != nil {
                    return event // already in detail, pass through
                }
                if self.focusedIndex >= 0, self.focusedIndex < agents.count {
                    self.selectAgent(agents[self.focusedIndex])
                }
                return nil
            case 53: // escape
                if self.selectedAgent != nil {
                    self.deselectAgent()
                } else if self.showHistory {
                    self.showHistory = false
                    // fixed size, no resize needed
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

        // Fixed sizes — no dynamic resizing. SwiftUI ScrollView handles content.
        let target = NotchGeometry.frame(for: state, on: screen)

        animating = true
        panel.setFrame(target, display: true)
        let expanding = (state == .expanded)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(expanding ? 400 : 100))
            self.animating = false
        }
    }
}
