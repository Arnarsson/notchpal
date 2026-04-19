import SwiftUI

/// Represents a single agent's status in the notch UI.
@Observable
final class AgentStatus: Identifiable {
    let id: String
    var agent: String
    var label: String
    var state: State = .idle

    enum State: String {
        case idle
        case busy
        case attention
        case error

        var color: Color {
            switch self {
            case .idle: .secondary
            case .busy: .green
            case .attention: .yellow
            case .error: .red
            }
        }
    }

    init(id: String, agent: String, label: String = "idle", state: State = .idle) {
        self.id = id
        self.agent = agent
        self.label = label
        self.state = state
    }
}

/// Registry of all agent statuses. The single source of truth for the notch content.
@Observable
final class AgentRegistry {
    static let shared = AgentRegistry()

    private(set) var agents: [AgentStatus] = []

    /// The highest-priority state across all agents (for the collapsed dot).
    var summaryState: AgentStatus.State {
        if agents.contains(where: { $0.state == .error }) { return .error }
        if agents.contains(where: { $0.state == .attention }) { return .attention }
        if agents.contains(where: { $0.state == .busy }) { return .busy }
        return .idle
    }

    private init() {
        // Seed with default HEKLA agent for backwards compatibility
        agents.append(AgentStatus(id: "hekla", agent: "HEKLA"))
    }

    func agent(id: String) -> AgentStatus? {
        agents.first { $0.id == id }
    }

    func addAgent(id: String, name: String) -> AgentStatus {
        if let existing = agent(id: id) { return existing }
        let status = AgentStatus(id: id, agent: name)
        agents.append(status)
        return status
    }

    func removeAgent(id: String) {
        agents.removeAll { $0.id == id }
    }

    // MARK: - LLDB helpers

    /// Set status on an agent by id. Creates the agent if it doesn't exist.
    ///   expr -l objc++ -- (void)[NSClassFromString(@"NotchPal.AgentRegistry") debugSetAgent:@"hekla" label:@"indexing 342 files" state:@"busy"]
    @objc static func debugSetAgent(_ agentId: String, label: String, state: String) {
        let registry = shared
        let status = registry.agent(id: agentId) ?? registry.addAgent(id: agentId, name: agentId)
        status.label = label
        status.state = AgentStatus.State(rawValue: state) ?? .idle
    }

    /// Add a demo agent for testing multi-agent display.
    ///   expr -l objc++ -- (void)[NSClassFromString(@"NotchPal.AgentRegistry") debugAddDemo]
    @objc static func debugAddDemo() {
        let r = shared
        let hekla = r.agent(id: "hekla") ?? r.addAgent(id: "hekla", name: "HEKLA")
        hekla.label = "Arkivar indexing 342 files"
        hekla.state = .busy

        let arkivar = r.addAgent(id: "arkivar", name: "Arkivar")
        arkivar.label = "3 files reference deprecated API"
        arkivar.state = .attention

        let patentopia = r.addAgent(id: "patentopia", name: "Patentopia")
        patentopia.label = "Monitoring 12 claims"
        patentopia.state = .idle
    }
}
