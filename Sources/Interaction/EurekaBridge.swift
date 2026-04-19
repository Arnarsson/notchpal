import Foundation
import AppKit

/// Bridges NotchPal to the Eureka/OpenClaw API running on the Linux box.
/// Polls endpoints every few seconds and updates AgentRegistry with real data.
@Observable
final class EurekaBridge {
    static let shared = EurekaBridge()

    var baseURL = "http://100.83.83.58:8000"
    var isConnected = false
    var lastPoll: Date?
    var error: String?

    private var pollTimer: Task<Void, Never>?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Lifecycle

    func startPolling(interval: TimeInterval = 5) {
        pollTimer?.cancel()
        pollTimer = Task { @MainActor in
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Poll cycle

    private func poll() async {
        // Health
        await pollHealth()
        // Dashboard stats
        await pollDashboard()
        // Tasks
        await pollTasks()
        // Decisions
        await pollDecisions()
        // Comms
        await pollComms()

        lastPoll = Date()
    }

    // MARK: - Health

    private func pollHealth() async {
        guard let data = await fetch("/api/v2/health") else {
            isConnected = false
            return
        }
        isConnected = true

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared

            // Update or create infrastructure agent
            let infra = registry.agent(id: "infra") ?? registry.addAgent(id: "infra", name: "Infrastructure", icon: "server.rack")

            let services = ["server", "worker", "postgres", "qdrant", "redis", "agent"]
            let allOk = services.allSatisfy { (json[$0] as? String) == "ok" }
            let downServices = services.filter { (json[$0] as? String) != "ok" }

            if allOk {
                infra.state = .done
                infra.label = "All services healthy"
            } else {
                infra.state = .error
                infra.label = "\(downServices.joined(separator: ", ")) down"
            }
        }
    }

    // MARK: - Dashboard

    private func pollDashboard() async {
        guard let data = await fetch("/api/v2/dashboard/stats") else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared

            let dash = registry.agent(id: "dashboard") ?? registry.addAgent(id: "dashboard", name: "Dashboard", icon: "chart.bar.fill")
            let meetings = json["meetings_today"] as? Int ?? 0
            let inbound = json["inbound_count"] as? Int ?? 0
            let pending = json["pending_actions"] as? Int ?? 0

            dash.state = pending > 0 ? .attention : .done
            dash.label = "\(meetings) meetings · \(inbound) inbound · \(pending) pending"
        }
    }

    // MARK: - Tasks

    private func pollTasks() async {
        guard let data = await fetch("/api/v2/tasks?status=in_progress,todo") else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tasks = json["tasks"] as? [[String: Any]] {

            let registry = AgentRegistry.shared
            let taskAgent = registry.agent(id: "tasks") ?? registry.addAgent(id: "tasks", name: "Tasks", icon: "checklist")

            let inProgress = tasks.filter { ($0["status"] as? String) == "in_progress" }.count
            let todo = tasks.filter { ($0["status"] as? String) == "todo" }.count

            taskAgent.state = inProgress > 0 ? .busy : (todo > 0 ? .idle : .done)
            taskAgent.label = "\(inProgress) in progress · \(todo) todo"
        }
    }

    // MARK: - Decisions

    private func pollDecisions() async {
        guard let data = await fetch("/api/v2/decisions?status=pending") else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let decisions = json["decisions"] as? [[String: Any]] {

            let registry = AgentRegistry.shared
            let decAgent = registry.agent(id: "decisions") ?? registry.addAgent(id: "decisions", name: "Decisions", icon: "questionmark.circle.fill")

            if decisions.isEmpty {
                decAgent.state = .done
                decAgent.label = "No pending decisions"
            } else {
                decAgent.state = .attention
                let first = decisions.first?["title"] as? String ?? "Pending"
                decAgent.label = "\(decisions.count) pending · \(first)"
            }
        }
    }

    // MARK: - Comms

    private func pollComms() async {
        guard let data = await fetch("/api/v2/comms/summary") else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let comms = registry.agent(id: "comms") ?? registry.addAgent(id: "comms", name: "Comms", icon: "envelope.fill")

            let unread = json["unread"] as? Int ?? 0
            let priority = json["priority_threads"] as? Int ?? 0

            comms.state = priority > 0 ? .attention : (unread > 0 ? .busy : .idle)
            comms.label = "\(unread) unread · \(priority) priority"
        }
    }

    // MARK: - Command (Ask)

    func sendCommand(_ message: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/v2/command") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["message": message])

        do {
            let (data, _) = try await session.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? String {
                return response
            }
        } catch {}
        return nil
    }

    // MARK: - Decision actions

    func resolveDecision(id: String, action: String, note: String = "") async {
        guard let url = URL(string: "\(baseURL)/api/v2/decisions/\(id)/resolve") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "note": note])

        _ = try? await session.data(for: request)
    }

    // MARK: - Networking

    private func fetch(_ path: String) async -> Data? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
