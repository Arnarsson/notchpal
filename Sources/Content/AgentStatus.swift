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

    init(id: String, agent: String, label: String = "idle", state: State = .idle, progress: Double? = nil) {
        self.id = id
        self.agent = agent
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
    func addAgent(id: String, name: String) -> AgentStatus {
        if let existing = agent(id: id) { return existing }
        let status = AgentStatus(id: id, agent: name)
        agents.append(status)
        return status
    }

    func removeAgent(id: String) {
        agents.removeAll { $0.id == id }
    }

    func pushNotification(agent: String, message: String, state: AgentStatus.State = .done) {
        let notif = HUDNotification(agent: agent, message: message, state: state)
        notifications.append(notif)
        // Subtle system sound
        if state == .attention || state == .error {
            NSSound(named: .init("Basso"))?.play()
        } else {
            NSSound(named: .init("Pop"))?.play()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            notifications.removeAll { $0.id == notif.id }
        }
    }

    /// Generate file drop suggestions based on active agents.
    func suggestForDrop(_ url: URL) {
        dropSuggestions = [
            DropSuggestion(agentId: "chat", agentName: "Chat", action: "Summarize", icon: "text.magnifyingglass"),
            DropSuggestion(agentId: "memory", agentName: "Memory", action: "Index", icon: "brain"),
            DropSuggestion(agentId: "meeting", agentName: "Meeting Prep", action: "Attach", icon: "paperclip"),
        ]
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
                "email": ["Polling Gmail…", "214 seen · 2 new priority", "Archiving newsletters…", "Last poll 12s ago", "Drafting reply…"],
                "meeting": ["Pulling Linear tickets…", "Scanning calendar…", "Drafting agenda §2…", "Linking Notion docs…", "Formatting prep notes…"],
                "memory": ["Embedding batch 14/18…", "326 → 304 in queue", "Indexing email threads…", "Ollama latency 38ms", "Compacting vectors…"],
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

        let briefing = r.addAgent(id: "briefing", name: "Briefing")
        briefing.label = "Delivered 06:45 · 3 meetings"
        briefing.state = .done

        let meeting = r.addAgent(id: "meeting", name: "Meeting Prep")
        meeting.label = "Prepping. Ready in ~90s."
        meeting.state = .busy
        meeting.progress = 0.55

        let email = r.addAgent(id: "email", name: "Emails")
        email.label = "Last poll 42s ago"
        email.state = .busy
        email.progress = nil

        let telegram = r.addAgent(id: "telegram", name: "Telegram")
        telegram.label = "Reply to Peder · confidence 0.71"
        telegram.state = .attention

        let chat = r.addAgent(id: "chat", name: "Chat")
        chat.label = "Ready. Web search enabled."
        chat.state = .idle

        let memory = r.addAgent(id: "memory", name: "Memory")
        memory.label = "Embedding. 326 in queue."
        memory.state = .busy
        memory.progress = 0.22

        let log = r.addAgent(id: "log", name: "Log")
        log.label = "47 today · last action 2m ago"
        log.state = .done

        r.startProgressSimulation()
    }

    @objc static func debugPushNotification() {
        shared.pushNotification(agent: "Briefing", message: "Morning digest delivered via Telegram")
    }
}
