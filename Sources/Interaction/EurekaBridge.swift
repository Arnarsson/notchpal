import Foundation
import AppKit

/// Bridges NotchPal to the real Eureka API via SSH tunnel.
/// Every agent card maps to a real endpoint — no mock data.
@Observable
final class EurekaBridge {
    static let shared = EurekaBridge()

    var baseURL = "http://127.0.0.1:8888"
    var isConnected = false
    var lastPoll: Date?
    var error: String?

    private var pollTimer: Task<Void, Never>?
    private let session: URLSession
    private var consecutiveFailures = 0

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    func startPolling(interval: TimeInterval = 5) {
        pollTimer?.cancel()
        pollTimer = Task { @MainActor in
            while !Task.isCancelled {
                await poll()
                let wait: TimeInterval = consecutiveFailures >= 10 ? 30 : (consecutiveFailures >= 3 ? 15 : interval)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stopPolling() {
        pollTimer?.cancel()
    }

    // MARK: - Poll

    private func poll() async {
        guard let _ = await fetch("/health/") else {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 { isConnected = false }
            return
        }
        consecutiveFailures = 0
        isConnected = true

        await pollEureka()
        await pollEmail()
        await pollCalendar()
        await pollIssues()
        await pollActivity()
        await pollInsights()
        lastPoll = Date()
    }

    // MARK: - Eureka core status

    private func pollEureka() async {
        guard let data = await fetch("/api/eureka/status") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "eureka") ?? r.addAgent(id: "eureka", name: "Eureka", icon: "bolt.fill")

        let online = json["online"] as? Bool ?? false
        let model = json["model"] as? String ?? "?"
        let workers = json["activeWorkers"] as? [[String: Any]] ?? []

        if !workers.isEmpty {
            agent.state = .busy
            agent.label = "\(workers.count) workers · \(model)"
        } else if online {
            agent.state = .idle
            agent.label = "Online · \(model)"
        } else {
            agent.state = .error
            agent.label = "Offline"
        }
    }

    // MARK: - Email

    private func pollEmail() async {
        guard let data = await fetch("/api/email/categories/counts") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categories = json["categories"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "email") ?? r.addAgent(id: "email", name: "Email", icon: "envelope.fill")

        let priority = categories.first { ($0["name"] as? String) == "priority" }
        let unread = priority?["unread"] as? Int ?? 0
        let total = categories.reduce(0) { $0 + (($1["unread"] as? Int) ?? 0) }

        agent.state = unread > 10 ? .attention : (total > 0 ? .busy : .idle)
        agent.label = "\(unread) priority · \(total) total unread"
    }

    // MARK: - Calendar

    private func pollCalendar() async {
        guard let data = await fetch("/api/calendar/events/upcoming") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "calendar") ?? r.addAgent(id: "calendar", name: "Calendar", icon: "calendar")

        if events.isEmpty {
            agent.state = .idle
            agent.label = "No upcoming events"
        } else {
            let next = events.first?["summary"] as? String ?? "Event"
            agent.state = .done
            agent.label = "\(events.count) upcoming · \(next)"
        }
    }

    // MARK: - Issues/Projects

    private func pollIssues() async {
        guard let data = await fetch("/api/issues") else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "issues") ?? r.addAgent(id: "issues", name: "Issues", icon: "list.bullet.rectangle")

        if let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let todo = items.filter { ($0["status"] as? String) == "todo" }.count
            let backlog = items.filter { ($0["status"] as? String) == "backlog" }.count
            agent.state = todo > 0 ? .busy : .idle
            agent.label = "\(todo) todo · \(backlog) backlog · \(items.count) total"
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["issues"] as? [[String: Any]] {
            agent.state = items.isEmpty ? .idle : .busy
            agent.label = "\(items.count) issues"
        }
    }

    // MARK: - Activity

    private func pollActivity() async {
        guard let data = await fetch("/api/activity/summary") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "activity") ?? r.addAgent(id: "activity", name: "Activity", icon: "eye.fill")

        let captures = json["total_captures"] as? Int ?? 0
        let hours = json["active_hours"] as? Int ?? 0

        agent.state = captures > 0 ? .done : .idle
        agent.label = "\(captures) captures · \(hours)h active today"
    }

    // MARK: - Insights (stuck items)

    private func pollInsights() async {
        guard let data = await fetch("/api/insights/suggested-actions") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = json["actions"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "insights") ?? r.addAgent(id: "insights", name: "Insights", icon: "lightbulb.fill")

        let high = actions.filter { ($0["priority"] as? String) == "high" }
        if high.isEmpty {
            agent.state = .idle
            agent.label = "No actions needed"
        } else {
            let first = high.first?["title"] as? String ?? ""
            // Trim "Escalate: " prefix
            let clean = first.hasPrefix("Escalate: ") ? String(first.dropFirst(10)) : first
            agent.state = .attention
            agent.label = "\(high.count) flagged · \(clean)"
        }
    }

    // MARK: - Ask (command)

    func sendCommand(_ message: String) async -> String? {
        // Try catchup
        guard let url = URL(string: "\(baseURL)/api/catchup/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["topic": message])

        do {
            let (data, _) = try await session.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? String {
                return summary
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Networking

    private func fetch(_ path: String) async -> Data? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
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
