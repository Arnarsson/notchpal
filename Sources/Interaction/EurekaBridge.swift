import Foundation
import AppKit

/// Bridges NotchPal to real Eureka API. No mock data. No inferred summaries.
/// Every card shows raw timestamped facts from a known endpoint.
@Observable
final class EurekaBridge {
    static let shared = EurekaBridge()

    var baseURL = "https://platanvejomarchy.tail12cdd5.ts.net"
    var isConnected = false
    var lastPoll: Date?
    var error: String?
    var aiOnline = false
    var chatEndpoint: String?

    // Priority data for compact state
    var priorityEmailCount = 0
    var stuckIssueCount = 0
    var nextEventName: String?
    var nextEventTime: String?
    var activeWorkerCount = 0

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
            await discoverChatEndpoint()
            while !Task.isCancelled {
                await poll()
                let wait: TimeInterval = consecutiveFailures >= 10 ? 30 : (consecutiveFailures >= 3 ? 15 : interval)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stopPolling() { pollTimer?.cancel() }

    // MARK: - Chat endpoint discovery

    private func discoverChatEndpoint() async {
        guard let data = await fetch("/openapi.json") else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["paths"] as? [String: Any] else { return }

        let keywords = ["compose", "chat", "query", "ask", "command", "catchup"]
        let candidates = paths.keys.filter { path in
            let lower = path.lowercased()
            return keywords.contains { lower.contains($0) }
        }
        // Prefer POST endpoints, shortest path
        let postCandidates = candidates.filter { path in
            guard let methods = paths[path] as? [String: Any] else { return false }
            return methods.keys.contains("post")
        }.sorted { $0.count < $1.count }

        chatEndpoint = postCandidates.first ?? candidates.sorted(by: { $0.count < $1.count }).first
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
        await pollInboxTriage()
        await pollCalendar()
        await pollIssues()
        await pollOpenLoops()
        await pollActivity()
        await pollInsights()
        await pollBridge()
        lastPoll = Date()
    }

    // MARK: - Helpers

    private func stamp(_ agent: AgentStatus, endpoint: String) {
        agent.lastUpdated = Date()
        agent.sourceEndpoint = endpoint
    }

    // MARK: - Eureka

    private func pollEureka() async {
        let ep = "/api/eureka/status"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "eureka") ?? r.addAgent(id: "eureka", name: "Eureka", icon: "bolt.fill")
        stamp(agent, endpoint: ep)

        let online = json["online"] as? Bool ?? false
        let model = json["model"] as? String ?? "?"
        let workers = json["activeWorkers"] as? [[String: Any]] ?? []

        activeWorkerCount = workers.count
        if !workers.isEmpty {
            agent.state = .busy
            agent.label = "\(workers.count) workers · \(model)"
        } else if online {
            agent.state = .idle
            agent.label = "\(model)"
        } else {
            agent.state = .error
            agent.label = "Offline"
        }

        // Check AI credits by trying a lightweight call
        aiOnline = online // will refine below
    }

    // MARK: - Email

    private func pollEmail() async {
        let ep = "/api/email/categories/counts"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categories = json["categories"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "email") ?? r.addAgent(id: "email", name: "Email", icon: "envelope.fill")
        stamp(agent, endpoint: ep)

        let priority = categories.first { ($0["name"] as? String) == "priority" }
        let priorityUnread = priority?["unread"] as? Int ?? 0
        let totalUnread = categories.reduce(0) { $0 + (($1["unread"] as? Int) ?? 0) }

        priorityEmailCount = priorityUnread
        agent.state = priorityUnread > 10 ? .attention : (totalUnread > 0 ? .busy : .idle)
        agent.label = "\(priorityUnread) priority · \(totalUnread) total unread"
    }

    // MARK: - Calendar

    private func pollCalendar() async {
        let ep = "/api/calendar/events/upcoming"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "calendar") ?? r.addAgent(id: "calendar", name: "Calendar", icon: "calendar")
        stamp(agent, endpoint: ep)

        if events.isEmpty {
            agent.state = .idle
            agent.label = "No upcoming"
            nextEventName = nil
            nextEventTime = nil
        } else {
            let next = events.first?["summary"] as? String ?? "Event"
            let start = (events.first?["start"] as? String ?? "").prefix(16)
            nextEventName = next
            nextEventTime = String(start.suffix(5)) // HH:MM
            agent.state = .done
            agent.label = "\(events.count) upcoming · \(next)"
        }
    }

    // MARK: - Issues

    private func pollIssues() async {
        let ep = "/api/issues"
        guard let data = await fetch(ep) else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "issues") ?? r.addAgent(id: "issues", name: "Issues", icon: "list.bullet.rectangle")
        stamp(agent, endpoint: ep)

        if let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let todo = items.filter { ($0["status"] as? String) == "todo" }.count
            let backlog = items.filter { ($0["status"] as? String) == "backlog" }.count
            agent.state = todo > 0 ? .busy : .idle
            agent.label = "\(todo) todo · \(backlog) backlog"
        }
    }

    // MARK: - Activity

    private func pollActivity() async {
        let ep = "/api/activity/summary"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "activity") ?? r.addAgent(id: "activity", name: "Activity", icon: "eye.fill")
        stamp(agent, endpoint: ep)

        let captures = json["total_captures"] as? Int ?? 0
        let hours = json["active_hours"] as? Int ?? 0
        agent.state = .done
        agent.label = "\(captures) captures · \(hours)h active"
    }

    // MARK: - Insights

    private func pollInsights() async {
        let ep = "/api/insights/suggested-actions"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actions = json["actions"] as? [[String: Any]] else { return }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "insights") ?? r.addAgent(id: "insights", name: "Insights", icon: "lightbulb.fill")
        stamp(agent, endpoint: ep)

        let high = actions.filter { ($0["priority"] as? String) == "high" }
        if high.isEmpty {
            agent.state = .idle
            agent.label = "Nothing flagged"
        } else {
            let title = (high.first?["title"] as? String ?? "")
                .replacingOccurrences(of: "Escalate: ", with: "")
            agent.state = .attention
            agent.label = "\(high.count) flagged · \(title)"
        }
    }

    // MARK: - Direct Bridge panel

    private func pollBridge() async {
        let r = AgentRegistry.shared
        let agent = r.agent(id: "bridge") ?? r.addAgent(id: "bridge", name: "Direct Bridge", icon: "antenna.radiowaves.left.and.right")
        stamp(agent, endpoint: chatEndpoint ?? "none")

        if let ep = chatEndpoint {
            agent.state = .idle
            agent.label = "Chat: POST \(ep)"
        } else {
            agent.state = .error
            agent.label = "No direct chat endpoint found"
        }
    }

    // MARK: - Inbox Triage

    private func pollInboxTriage() async {
        let ep = "/api/inbox/triage"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let priority = json["priority"] as? [[String: Any]] ?? []
        priorityEmailCount = max(priorityEmailCount, priority.count)
    }

    // MARK: - Open Loops

    private func pollOpenLoops() async {
        let ep = "/api/insights/patterns"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let patterns = json["patterns"] as? [[String: Any]] else { return }

        let stuck = patterns.first { ($0["type"] as? String) == "stuck" }
        let ids = stuck?["issue_ids"] as? [String] ?? []
        stuckIssueCount = ids.count
    }

    // MARK: - Quick Actions

    func syncEmail() async {
        _ = await postAction("/api/email/sync")
        AgentRegistry.shared.pushNotification(agent: "Email", message: "Sync triggered", state: .busy)
    }

    func morningBriefing() async -> String? {
        guard let data = await fetch("/api/catchup/morning") else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["briefing"] as? String ?? json["summary"] as? String
        }
        return String(data: data, encoding: .utf8)
    }

    func archiveNewsletters() async {
        _ = await postAction("/api/inbox/archive-rest")
        AgentRegistry.shared.pushNotification(agent: "Inbox", message: "Newsletters archived", state: .done)
    }

    func spawnWorker(task: String = "Check status and report") async {
        guard let url = URL(string: "\(baseURL)/api/eureka/spawn") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["task": task])
        _ = try? await session.data(for: request)
        AgentRegistry.shared.pushNotification(agent: "Eureka", message: "Worker spawned", state: .busy)
    }

    private func postAction(_ path: String) async -> Data? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try? await session.data(for: request).0
    }

    // MARK: - Send command

    func sendCommand(_ message: String) async -> String? {
        let ep = chatEndpoint ?? "/api/catchup/"
        guard let url = URL(string: "\(baseURL)\(ep)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["topic": message, "message": message, "query": message])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "Error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for AI credit error
                if let summary = json["summary"] as? String, summary.contains("credit balance is too low") {
                    aiOnline = false
                    return "AI offline — Anthropic credits exhausted. Live data cards still active."
                }
                return json["summary"] as? String
                    ?? json["response"] as? String
                    ?? json["text"] as? String
                    ?? String(data: data, encoding: .utf8)
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return "Error: \(error.localizedDescription)"
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
