import SwiftUI
import AppKit

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

@Observable
final class AgentStatus: Identifiable {
    let id: String
    var agent: String
    var icon: String  // SF Symbol name
    var label: String
    var state: State = .idle
    var progress: Double?
    var justCompleted = false

    enum State: String {
        case idle, busy, attention, error, done

        var color: Color {
            switch self {
            case .idle: Color(hex: 0x807A72)
            case .busy: Color(hex: 0xD4643A)
            case .attention: Color(hex: 0xFEBC2E)
            case .error: Color(hex: 0xFF5F57)
            case .done: Color(hex: 0x28C840)
            }
        }

        var statusLabel: String {
            switch self {
            case .idle: "IDLE"
            case .busy: "WORKING"
            case .attention: "NEEDS YOU"
            case .error: "ERROR"
            case .done: "DONE"
            }
        }
    }

    init(id: String, agent: String, icon: String = "circle.fill", label: String = "idle", state: State = .idle, progress: Double? = nil) {
        self.id = id
        self.agent = agent
        self.icon = icon
        self.label = label
        self.state = state
        self.progress = progress
    }
}

@Observable
final class HUDNotification: Identifiable {
    let id = UUID()
    let agent: String
    let message: String
    let state: AgentStatus.State

    init(agent: String, message: String, state: AgentStatus.State = .done) {
        self.agent = agent
        self.message = message
        self.state = state
    }
}

/// Suggestion for what to do with a dropped file.
struct DropSuggestion: Identifiable {
    let id = UUID()
    let agentId: String
    let agentName: String
    let action: String
    let icon: String
}

@Observable
final class AgentRegistry {
    static let shared = AgentRegistry()

    private(set) var agents: [AgentStatus] = []
    var notifications: [HUDNotification] = []
    var notificationHistory: [HUDNotification] = []  // persistent history
    var dropSuggestions: [DropSuggestion] = []
    private var progressTimer: Task<Void, Never>?

    var summaryState: AgentStatus.State {
        if agents.contains(where: { $0.state == .error }) { return .error }
        if agents.contains(where: { $0.state == .attention }) { return .attention }
        if agents.contains(where: { $0.state == .busy }) { return .busy }
        return .idle
    }

    var workingCount: Int { agents.filter { $0.state == .busy }.count }
    var needsYouCount: Int { agents.filter { $0.state == .attention }.count }
    var doneCount: Int { agents.filter { $0.state == .done }.count }

    private init() {
        agents.append(AgentStatus(id: "hekla", agent: "HEKLA"))
    }

    func agent(id: String) -> AgentStatus? {
        agents.first { $0.id == id }
    }

    @discardableResult
    func addAgent(id: String, name: String, icon: String = "circle.fill") -> AgentStatus {
        if let existing = agent(id: id) { return existing }
        let status = AgentStatus(id: id, agent: name, icon: icon)
        agents.append(status)
        return status
    }

    func removeAgent(id: String) {
        agents.removeAll { $0.id == id }
    }

    func pushNotification(agent: String, message: String, state: AgentStatus.State = .done) {
        let notif = HUDNotification(agent: agent, message: message, state: state)
        notifications.append(notif)
        notificationHistory.insert(notif, at: 0)
        // Keep history to 50 max
        if notificationHistory.count > 50 { notificationHistory.removeLast() }
        // Sound
        if state == .attention || state == .error {
            NSSound(named: .init("Basso"))?.play()
        } else {
            NSSound(named: .init("Pop"))?.play()
        }
        // Auto-dismiss from live stack after 3s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            notifications.removeAll { $0.id == notif.id }
        }
    }

    /// Generate file drop suggestions based on active agents.
    func suggestForDrop(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp"].contains(ext) {
            dropSuggestions = [
                DropSuggestion(agentId: "art", agentName: "Art Core", action: "Style Transfer", icon: "paintbrush.pointed.fill"),
                DropSuggestion(agentId: "animation", agentName: "Animation Core", action: "Add to Sprite", icon: "film.stack"),
                DropSuggestion(agentId: "data", agentName: "Data Core", action: "Index", icon: "cylinder.split.1x2"),
            ]
        } else {
            dropSuggestions = [
                DropSuggestion(agentId: "data", agentName: "Data Core", action: "Index", icon: "cylinder.split.1x2"),
                DropSuggestion(agentId: "story", agentName: "Story Core", action: "Add Context", icon: "book.fill"),
                DropSuggestion(agentId: "coach", agentName: "Coach Core", action: "Analyze", icon: "person.wave.2.fill"),
            ]
        }
    }

    func clearDropSuggestions() {
        dropSuggestions = []
    }

    /// Approve/dismiss a Telegram draft (or any attention agent).
    func approveAgent(id: String, action: String) {
        guard let agent = agent(id: id) else { return }
        let name = agent.agent
        agent.state = .done
        agent.label = action == "send" ? "Reply sent" : "Draft rejected"
        pushNotification(
            agent: name,
            message: action == "send" ? "Reply sent to Peder K." : "Draft discarded",
            state: action == "send" ? .done : .idle
        )
    }

    /// Start live progress ticking and activity text cycling for working agents.
    func startProgressSimulation() {
        progressTimer?.cancel()
        progressTimer = Task { @MainActor in
            let activityPhrases: [String: [String]] = [
                "art": ["SDXL · Loading LoRA weights…", "Generating keyframe 4/8…", "ComfyUI · Style transfer pass…", "Particle map extraction…", "Upscaling 2× with ESRGAN…"],
                "animation": ["RIFE · Interpolating frames…", "Building sprite sheet…", "24 → 18 frames remaining", "Generating metadata JSON…", "Overlay particle data…"],
                "data": ["ChromaDB · Indexing new docs…", "Embedding batch 12/14…", "Ollama · 38ms latency", "4,812 → 4,826 vectors", "RAG query cache warm"],
            ]
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                tick += 1
                for agent in agents where agent.state == .busy {
                    // Tick progress
                    if let p = agent.progress, p < 1.0 {
                        agent.progress = min(p + Double.random(in: 0.01...0.03), 1.0)
                        if agent.progress! >= 1.0 {
                            agent.state = .done
                            agent.label = "Complete"
                            agent.progress = nil
                            agent.justCompleted = true
                            pushNotification(agent: agent.agent, message: "Finished")
                            // Clear flash after 1s
                            let a = agent
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1))
                                a.justCompleted = false
                            }
                            continue
                        }
                    }
                    // Cycle activity text
                    if let phrases = activityPhrases[agent.id] {
                        agent.label = phrases[tick % phrases.count]
                    }
                }
            }
        }
    }

    // MARK: - LLDB helpers

    @objc static func debugSetAgent(_ agentId: String, label: String, state: String) {
        let registry = shared
        let status = registry.agent(id: agentId) ?? registry.addAgent(id: agentId, name: agentId)
        status.label = label
        status.state = AgentStatus.State(rawValue: state) ?? .idle
    }

    @objc static func debugAddDemo() {
        let r = shared
        r.agents.removeAll()

        // OpenClaw Cores
        let data = r.addAgent(id: "data", name: "Data Core", icon: "cylinder.split.1x2")
        data.label = "ChromaDB · 4,812 vectors indexed"
        data.state = .done

        let art = r.addAgent(id: "art", name: "Art Core", icon: "paintbrush.pointed.fill")
        art.label = "SDXL · Generating keyframe batch 3/8"
        art.state = .busy
        art.progress = 0.38

        let animation = r.addAgent(id: "animation", name: "Animation Core", icon: "film.stack")
        animation.label = "RIFE interpolation · 24 frames queued"
        animation.state = .busy
        animation.progress = 0.62

        let coach = r.addAgent(id: "coach", name: "Coach Core", icon: "person.wave.2.fill")
        coach.label = "Arnold · Nemotron 8B · listening"
        coach.state = .idle

        let story = r.addAgent(id: "story", name: "Story Core", icon: "book.fill")
        story.label = "Chapter 3 draft needs review"
        story.state = .attention

        // Infrastructure
        let screen = r.addAgent(id: "screenshare", name: "Screen Share", icon: "rectangle.inset.filled.and.person.filled")
        screen.label = "Not sharing"
        screen.state = .idle

        let log = r.addAgent(id: "log", name: "Log", icon: "list.bullet.rectangle")
        log.label = "142 actions today"
        log.state = .done

        r.startProgressSimulation()
    }

    @objc static func debugPushNotification() {
        shared.pushNotification(agent: "Briefing", message: "Morning digest delivered via Telegram")
    }
}
