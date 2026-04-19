import Foundation
import AppKit

/// Bridges NotchPal to the Eureka/OpenClaw API.
/// Uses EndpointResolver to discover paths dynamically — no hardcoded routes.
@Observable
final class EurekaBridge {
    static let shared = EurekaBridge()

    // SSH tunnel: localhost:8888 → 100.83.83.58:8000
    var baseURL = "http://127.0.0.1:8888"
    var isConnected = false
    var lastPoll: Date?
    var error: String?

    private var pollTimer: Task<Void, Never>?
    private let session: URLSession
    private let resolver = EndpointResolver.shared
    private var consecutiveFailures = 0

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
            // Initial discovery
            await resolver.discover(baseURL: baseURL)

            while !Task.isCancelled {
                await poll()

                // Backoff: 5s normal, 15s after 3 failures, 30s after 10
                let wait: TimeInterval
                if consecutiveFailures >= 10 {
                    wait = 30
                } else if consecutiveFailures >= 3 {
                    wait = 15
                } else {
                    wait = interval
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Poll cycle

    private func poll() async {
        let healthOk = await pollHealth()

        if healthOk {
            consecutiveFailures = 0
            isConnected = true

            await pollEurekaStatus()
            await pollDashboard()
            await pollTasks()
            await pollDecisions()
            await pollComms()
            await pollCalendar()
            lastPoll = Date()
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                isConnected = false
            }

            // Re-discover if we've been failing (endpoints may have changed)
            if consecutiveFailures == 5 {
                await resolver.discover(baseURL: baseURL)
            }
        }
    }

    // MARK: - Health

    private func pollHealth() async -> Bool {
        // Try resolved health endpoint
        if let url = resolver.url(for: .health, baseURL: baseURL) {
            if let data = await fetch(url: url) {
                updateInfraAgent(from: data)
                return true
            }
        }

        // Fallback probes
        for path in ["/health/", "/health/ready", "/api/v2/health"] {
            if let url = URL(string: "\(baseURL)\(path)"),
               let _ = await fetch(url: url) {
                return true
            }
        }

        return false
    }

    private func updateInfraAgent(from data: Data) {
        let registry = AgentRegistry.shared
        let infra = registry.agent(id: "infra") ?? registry.addAgent(id: "infra", name: "Infrastructure", icon: "server.rack")

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let services = json.keys.filter { $0 != "status" && $0 != "ready" }
            let down = services.filter { (json[$0] as? String) != "ok" && (json[$0] as? Bool) != true }

            if down.isEmpty {
                infra.state = .done
                infra.label = "All services healthy"
            } else {
                infra.state = .error
                infra.label = "\(down.joined(separator: ", ")) down"
            }
        } else {
            infra.state = .done
            infra.label = "Reachable"
        }
    }

    // MARK: - Eureka Workers

    private func pollEurekaStatus() async {
        guard let url = URL(string: "\(baseURL)/api/eureka/status"),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let eureka = registry.agent(id: "eureka") ?? registry.addAgent(id: "eureka", name: "Eureka", icon: "bolt.fill")

            let online = json["online"] as? Bool ?? false
            let model = json["model"] as? String ?? "unknown"
            let workers = json["activeWorkers"] as? [[String: Any]] ?? []

            if !workers.isEmpty {
                eureka.state = .busy
                eureka.label = "\(workers.count) active · \(model)"
            } else if online {
                eureka.state = .idle
                eureka.label = "Online · \(model)"
            } else {
                eureka.state = .error
                eureka.label = "Offline"
            }
        }
    }

    // MARK: - Dashboard

    private func pollDashboard() async {
        guard let url = resolver.url(for: .dashboard, baseURL: baseURL),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let dash = registry.agent(id: "dashboard") ?? registry.addAgent(id: "dashboard", name: "Dashboard", icon: "chart.bar.fill")

            // Handle both flat stats and nested {stats: {}} responses
            let stats = (json["stats"] as? [String: Any]) ?? json
            let meetings = stats["meetings_today"] as? Int ?? stats["meetings"] as? Int ?? 0
            let inbound = stats["inbound_count"] as? Int ?? stats["inbound"] as? Int ?? 0
            let pending = stats["pending_actions"] as? Int ?? stats["pending"] as? Int ?? 0

            dash.state = pending > 0 ? .attention : .done
            dash.label = "\(meetings) meetings · \(inbound) inbound · \(pending) pending"
        }
    }

    // MARK: - Tasks

    private func pollTasks() async {
        guard let url = resolver.url(for: .tasks, baseURL: baseURL),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let taskAgent = registry.agent(id: "tasks") ?? registry.addAgent(id: "tasks", name: "Tasks", icon: "checklist")

            // Handle array or {tasks: []} or {issues: []}
            let items: [[String: Any]]
            if let t = json["tasks"] as? [[String: Any]] { items = t }
            else if let i = json["issues"] as? [[String: Any]] { items = i }
            else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { items = arr }
            else { items = [] }

            let inProgress = items.filter { ($0["status"] as? String)?.contains("progress") == true }.count
            let todo = items.filter { ($0["status"] as? String) == "todo" || ($0["status"] as? String) == "backlog" }.count

            taskAgent.state = inProgress > 0 ? .busy : (todo > 0 ? .idle : .done)
            taskAgent.label = "\(inProgress) in progress · \(todo) todo"
        }
    }

    // MARK: - Decisions

    private func pollDecisions() async {
        guard let url = resolver.url(for: .decisions, baseURL: baseURL),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let decAgent = registry.agent(id: "decisions") ?? registry.addAgent(id: "decisions", name: "Decisions", icon: "questionmark.circle.fill")

            let decisions: [[String: Any]]
            if let d = json["decisions"] as? [[String: Any]] { decisions = d }
            else if let d = json["pending"] as? [[String: Any]] { decisions = d }
            else { decisions = [] }

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
        guard let url = resolver.url(for: .comms, baseURL: baseURL),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let registry = AgentRegistry.shared
            let comms = registry.agent(id: "comms") ?? registry.addAgent(id: "comms", name: "Comms", icon: "envelope.fill")

            let unread = json["unread"] as? Int ?? json["total_unread"] as? Int ?? 0
            let priority = json["priority_threads"] as? Int ?? json["priority"] as? Int ?? 0

            comms.state = priority > 0 ? .attention : (unread > 0 ? .busy : .idle)
            comms.label = "\(unread) unread · \(priority) priority"
        }
    }

    // MARK: - Calendar

    private func pollCalendar() async {
        guard let url = URL(string: "\(baseURL)/api/calendar/events/upcoming"),
              let data = await fetch(url: url) else { return }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let events = json["events"] as? [[String: Any]] {
            let registry = AgentRegistry.shared
            let cal = registry.agent(id: "calendar") ?? registry.addAgent(id: "calendar", name: "Calendar", icon: "calendar")

            if events.isEmpty {
                cal.state = .idle
                cal.label = "No upcoming events"
            } else {
                let next = events.first?["summary"] as? String ?? "Event"
                cal.state = .done
                cal.label = "\(events.count) upcoming · Next: \(next)"
            }
        }
    }

    // MARK: - Command (Ask)

    func sendCommand(_ message: String) async -> String? {
        // Try resolved command endpoint, fall back to /api/catchup/quick
        let url: URL
        if let resolved = resolver.url(for: .command, baseURL: baseURL) {
            url = resolved
        } else if let fallback = URL(string: "\(baseURL)/api/catchup/quick") {
            url = fallback
        } else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["topic": message, "message": message])

        do {
            let (data, _) = try await session.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? String {
                return response
            }
            // Try plain text
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Decision actions

    func resolveDecision(id: String, action: String, note: String = "") async {
        guard let base = resolver.url(for: .decisions, baseURL: baseURL) else { return }
        guard let url = URL(string: "\(base.absoluteString)/\(id)/resolve") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "note": note])

        _ = try? await session.data(for: request)
    }

    // MARK: - Networking

    private func fetch(url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
