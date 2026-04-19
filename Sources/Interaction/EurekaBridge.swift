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
        await pollMeetingProximity()
        await pollIssues()
        await pollOpenLoops()
        await pollDaily3()
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

    // MARK: - Inbox Triage (Feature 2)

    var triageItems: [[String: Any]] = []

    private func pollInboxTriage() async {
        let ep = "/api/inbox/triage"
        guard let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let priority = json["priority"] as? [[String: Any]] ?? []
        triageItems = Array(priority.prefix(5))
        priorityEmailCount = priority.count

        let r = AgentRegistry.shared
        let agent = r.agent(id: "triage") ?? r.addAgent(id: "triage", name: "Inbox", icon: "tray.fill")
        stamp(agent, endpoint: ep)
        agent.state = priority.isEmpty ? .idle : .attention
        agent.label = "\(priority.count) need triage"
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

    // MARK: - Daily Focus (Feature 3)

    var daily3Items: [[String: Any]] = []

    private func pollDaily3() async {
        let ep = "/api/daily3/today"
        guard let data = await fetch(ep) else { return }

        if let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !items.isEmpty {
            daily3Items = items
            let r = AgentRegistry.shared
            let agent = r.agent(id: "daily3") ?? r.addAgent(id: "daily3", name: "Daily 3", icon: "target")
            stamp(agent, endpoint: ep)
            let done = items.filter { ($0["done"] as? Bool) == true }.count
            agent.state = done == items.count ? .done : .busy
            agent.label = "\(done)/\(items.count) complete"
        }
        // If null/404, don't register agent — graceful absence
    }

    // MARK: - Meeting Proximity (Feature 4)

    var imminentMeeting: [String: Any]?
    var meetingBrief: String?

    private func pollMeetingProximity() async {
        // Reuses calendar data already fetched
        guard let calAgent = AgentRegistry.shared.agent(id: "calendar"),
              let ep = calAgent.sourceEndpoint,
              let data = await fetch(ep),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            imminentMeeting = nil
            return
        }

        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for event in events {
            guard let startStr = event["start"] as? String,
                  let start = fmt.date(from: startStr) ?? ISO8601DateFormatter().date(from: startStr) else { continue }

            let minutesUntil = start.timeIntervalSince(now) / 60

            if minutesUntil > -5 && minutesUntil < 15 {
                let wasNil = imminentMeeting == nil
                imminentMeeting = event

                // Register meeting agent
                let r = AgentRegistry.shared
                let agent = r.agent(id: "meeting") ?? r.addAgent(id: "meeting", name: "Meeting", icon: "calendar.badge.clock")
                agent.state = .attention
                let title = event["summary"] as? String ?? "Meeting"
                agent.label = minutesUntil > 0 ? "In \(Int(minutesUntil))min: \(title)" : "Now: \(title)"
                stamp(agent, endpoint: ep)

                // Fetch brief if available
                if let eventId = event["id"] as? String {
                    if let briefData = await fetch("/api/meeting/\(eventId)/brief"),
                       let briefJson = try? JSONSerialization.jsonObject(with: briefData) as? [String: Any] {
                        meetingBrief = briefJson["brief"] as? String ?? briefJson["notes"] as? String
                    }
                }

                // HUD on first detection
                if wasNil {
                    AgentRegistry.shared.pushNotification(
                        agent: "Meeting",
                        message: "In \(max(1, Int(minutesUntil)))min: \(title)",
                        state: .attention
                    )
                }
                return
            }
        }

        // No imminent meeting — clean up
        if imminentMeeting != nil {
            imminentMeeting = nil
            meetingBrief = nil
            AgentRegistry.shared.removeAgent(id: "meeting")
        }
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

    // MARK: - Ask routing

    func sendCommandRouted(_ message: String) async -> String? {
        // 1. Prefer direct Eureka chat via OpenClaw ACP (same as Telegram)
        if OpenClawBridge.shared.isAvailable {
            if let reply = await OpenClawBridge.shared.chat(message) {
                return reply
            }
        }
        // 2. Try Eureka API catchup
        if let result = await sendCommand(message),
           !result.contains("credit balance is too low") {
            return result
        }
        // 3. Fallback: search memory
        return await searchMemory(message)
    }

    func searchMemory(_ query: String) async -> String? {
        guard let data = await fetch("/api/v2/bridge/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        if results.isEmpty { return "No results for '\(query)'" }

        // Format top 3 results
        let lines = results.prefix(3).map { r -> String in
            let title = r["title"] as? String ?? ""
            let snippet = (r["snippet"] as? String ?? "").prefix(100)
            let source = r["source"] as? String ?? ""
            let date = (r["date"] as? String ?? "").prefix(10)
            return "[\(source) · \(date)] \(title)\n\(snippet)"
        }
        return lines.joined(separator: "\n\n")
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

// MARK: - Feature 5: OpenClaw Agent Bridge (text chat)

/// Direct chat with Eureka via OpenClaw Gateway REST API.
/// Session locked to agent:main:notch:sven — talks to Eureka only.
///
/// Protocol (per Eureka spec):
///   POST /api/v1/session/send → {runId}
///   GET  /api/v1/session/stream?sessionKey=... → SSE (assistant.delta, assistant.done)
///   Auth: Authorization: Bearer <gateway-token>
@Observable
final class OpenClawBridge {
    static let shared = OpenClawBridge()

    let gatewayURL = "http://127.0.0.1:18789"  // via SSH tunnel
    let sessionKey = "agent:main:notch:sven"

    var isAvailable = false
    var lastError: String?
    var lastReply: String?
    var streaming = false
    var streamedText = ""

    private var gatewayToken: String? = ProcessInfo.processInfo.environment["OPENCLAW_TOKEN"]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        self.session = URLSession(configuration: config)
    }

    func probe() async {
        // Check if gateway session/send endpoint exists
        guard let url = URL(string: "\(gatewayURL)/api/v1/session/send") else {
            markOffline("Bad URL")
            return
        }

        // Also check basic health
        if let healthURL = URL(string: "\(gatewayURL)/health") {
            do {
                let (data, resp) = try await session.data(from: healthURL)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    markOffline("Gateway unhealthy")
                    return
                }
                // Check if session endpoints are available (404 = not implemented yet)
                let (_, sendResp) = try await session.data(from: url)
                let sendCode = (sendResp as? HTTPURLResponse)?.statusCode ?? 0
                // 405 Method Not Allowed = endpoint exists but needs POST
                // 401 = exists but needs auth
                // 404 = not implemented
                isAvailable = sendCode != 404
                if !isAvailable {
                    markOffline("Chat endpoints not deployed yet")
                }
            } catch {
                markOffline(error.localizedDescription)
            }
        }

        let r = AgentRegistry.shared
        let agent = r.agent(id: "openclaw") ?? r.addAgent(id: "openclaw", name: "Eureka Chat", icon: "sparkle")
        agent.state = isAvailable ? .idle : .error
        agent.label = isAvailable ? "Ready · \(sessionKey)" : (lastError ?? "Offline")
        agent.sourceEndpoint = "/api/v1/session/send"
        agent.lastUpdated = Date()
    }

    private func markOffline(_ reason: String) {
        isAvailable = false
        lastError = reason
    }

    /// Send a message and stream the reply.
    func chat(_ text: String) async -> String? {
        // If gateway chat endpoints aren't deployed, fall back to memory search
        guard isAvailable else {
            return await EurekaBridge.shared.searchMemory(text)
        }

        // 1. POST /api/v1/session/send
        guard let sendURL = URL(string: "\(gatewayURL)/api/v1/session/send") else { return nil }
        var request = URLRequest(url: sendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = gatewayToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let clientMessageId = UUID().uuidString
        let body: [String: Any] = [
            "sessionKey": sessionKey,
            "text": text,
            "clientMessageId": clientMessageId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else { return nil }

            if http.statusCode == 404 {
                // Endpoints not deployed yet — fall back
                isAvailable = false
                lastError = "Chat endpoints not deployed yet"
                return await EurekaBridge.shared.searchMemory(text)
            }

            guard (200..<300).contains(http.statusCode) else {
                lastError = "HTTP \(http.statusCode)"
                return "Error: HTTP \(http.statusCode)"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runId = json["runId"] as? String else {
                return "Error: invalid response"
            }

            // 2. Stream reply via SSE
            return await streamReply(runId: runId)

        } catch {
            lastError = error.localizedDescription
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Listen on SSE stream for the reply matching runId.
    private func streamReply(runId: String) async -> String? {
        guard let streamURL = URL(string: "\(gatewayURL)/api/v1/session/stream?sessionKey=\(sessionKey)") else { return nil }
        var request = URLRequest(url: streamURL)
        if let token = gatewayToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        streaming = true
        streamedText = ""
        defer { streaming = false }

        do {
            let (bytes, _) = try await session.bytes(for: request)

            for try await line in bytes.lines {
                // SSE format: "data: {json}"
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                let eventRunId = json["runId"] as? String
                guard eventRunId == runId || eventRunId == nil else { continue }

                let eventType = json["type"] as? String ?? ""

                switch eventType {
                case "assistant.delta":
                    if let delta = json["text"] as? String {
                        streamedText += delta
                    }
                case "assistant.done":
                    let finalText = json["text"] as? String ?? streamedText
                    lastReply = finalText
                    return finalText
                case "run.error":
                    let errorMsg = json["error"] as? String ?? "Unknown error"
                    lastError = errorMsg
                    return "Error: \(errorMsg)"
                default:
                    break // heartbeat, etc.
                }
            }
        } catch {
            lastError = error.localizedDescription
        }

        // If we got partial text, return it
        if !streamedText.isEmpty {
            lastReply = streamedText
            return streamedText
        }
        return nil
    }
}

// MARK: - Feature 6: Pair Session (screen + voice)
// Feature-flagged: set ENABLE_PAIR_SESSION=true env var to activate.

import CryptoKit

@Observable
final class PairSession {
    static let shared = PairSession()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ENABLE_PAIR_SESSION"] == "true"
    }

    enum Status: String { case idle, connecting, live, degraded, reconnecting, ended }
    var status: Status = .idle
    var sessionID = UUID().uuidString
    var conversationID: String?

    // Health
    var latencyMS: Int = 0
    var droppedFrames = 0
    var framesSent = 0
    var audioInSeconds: Double = 0
    var lastServerMessage: Date?
    var startTime: Date?

    var healthDot: AgentStatus.State {
        guard status == .live else { return status == .reconnecting ? .attention : .idle }
        if latencyMS > 600 || Date().timeIntervalSince(lastServerMessage ?? .distantPast) > 5 {
            return .attention
        }
        return .done
    }

    var elapsed: String {
        guard let start = startTime else { return "00:00" }
        let s = Int(Date().timeIntervalSince(start))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // Transcript
    struct Turn: Identifiable {
        let id = UUID()
        let role: String
        let text: String
        let ts: Date
    }
    var transcript: [Turn] = []

    // Dedup
    private var lastFrameHash: String?
    private var nextSeq = 0

    // WebSocket
    private var wsTask: URLSessionWebSocketTask?
    private var retryCount = 0

    private init() {}

    func start() async {
        guard Self.isEnabled else { return }
        guard status == .idle || status == .ended else { return }
        status = .connecting
        startTime = Date()
        transcript = []
        framesSent = 0
        droppedFrames = 0
        audioInSeconds = 0
        retryCount = 0

        // Register agent
        let r = AgentRegistry.shared
        let agent = r.agent(id: "pair") ?? r.addAgent(id: "pair", name: "Pair Session", icon: "person.2.wave.2.fill")
        agent.state = .busy
        agent.label = "Connecting…"

        await connect()
    }

    private func connect() async {
        let base = EurekaBridge.shared.baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        guard let url = URL(string: "\(base)/v1/pair") else {
            status = .ended
            return
        }

        let session = URLSession(configuration: .default)
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()

        // Send hello
        let hello: [String: Any] = [
            "type": "hello",
            "sessionID": sessionID,
            "conversationID": conversationID as Any,
            "capabilities": ["screen", "text"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: hello) {
            try? await wsTask?.send(.data(data))
        }

        status = .live
        if let agent = AgentRegistry.shared.agent(id: "pair") {
            agent.state = .busy
            agent.label = "Live · \(elapsed)"
        }

        AgentRegistry.shared.pushNotification(agent: "Pair", message: "Session started", state: .busy)

        // Start frame streaming
        startFrameLoop()

        // Listen for messages
        listenLoop()
    }

    private func startFrameLoop() {
        Task { @MainActor in
            let mgr = ScreenShareManager.shared
            if !mgr.isSharing {
                await mgr.startSharing()
            }

            while status == .live || status == .degraded {
                try? await Task.sleep(for: .seconds(0.5)) // 2 FPS

                guard let jpeg = mgr.latestFrameAsJPEG(quality: 0.5) else { continue }
                let hash = SHA256.hash(data: jpeg).compactMap { String(format: "%02x", $0) }.joined()

                if hash == lastFrameHash {
                    continue // dedup — identical frame
                }
                lastFrameHash = hash

                let frame: [String: Any] = [
                    "type": "frame",
                    "seq": nextSeq,
                    "ts": ISO8601DateFormatter().string(from: Date()),
                    "jpeg_base64": jpeg.base64EncodedString(),
                    "hash": hash
                ]
                nextSeq += 1

                if let data = try? JSONSerialization.data(withJSONObject: frame) {
                    do {
                        try await wsTask?.send(.data(data))
                        framesSent += 1
                    } catch {
                        droppedFrames += 1
                    }
                }
            }
        }
    }

    private func listenLoop() {
        Task {
            while status == .live || status == .degraded {
                guard let ws = wsTask else { break }
                do {
                    let message = try await ws.receive()
                    lastServerMessage = Date()

                    switch message {
                    case .data(let data):
                        handleServerMessage(data)
                    case .string(let str):
                        if let data = str.data(using: .utf8) {
                            handleServerMessage(data)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if status == .live {
                        await handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "text_delta":
            if let content = json["content"] as? String {
                Task { @MainActor in
                    if let last = transcript.last, last.role == "ai" {
                        transcript[transcript.count - 1] = Turn(role: "ai", text: last.text + content, ts: Date())
                    } else {
                        transcript.append(Turn(role: "ai", text: content, ts: Date()))
                    }
                }
            }
        case "ping":
            if let nonce = json["nonce"] {
                let pong: [String: Any] = ["type": "pong", "nonce": nonce]
                if let data = try? JSONSerialization.data(withJSONObject: pong) {
                    Task { try? await wsTask?.send(.data(data)) }
                }
            }
        case "error":
            let msg = json["message"] as? String ?? "Unknown error"
            Task { @MainActor in
                AgentRegistry.shared.pushNotification(agent: "Pair", message: msg, state: .error)
            }
        default:
            break
        }
    }

    private func handleDisconnect() async {
        status = .reconnecting
        if let agent = AgentRegistry.shared.agent(id: "pair") {
            agent.state = .attention
            agent.label = "Reconnecting…"
        }

        while retryCount < 5 && status == .reconnecting {
            retryCount += 1
            let delay = min(Double(1 << retryCount), 15) // 2,4,8,15,15
            try? await Task.sleep(for: .seconds(delay))
            await connect()
            if status == .live { return }
        }

        // Give up
        await end()
        AgentRegistry.shared.pushNotification(agent: "Pair", message: "Connection lost", state: .error)
    }

    func sendText(_ text: String) {
        transcript.append(Turn(role: "user", text: text, ts: Date()))
        let msg: [String: Any] = [
            "type": "text",
            "seq": nextSeq,
            "ts": ISO8601DateFormatter().string(from: Date()),
            "content": text
        ]
        nextSeq += 1
        if let data = try? JSONSerialization.data(withJSONObject: msg) {
            Task { try? await wsTask?.send(.data(data)) }
        }
    }

    func end() async {
        let bye: [String: Any] = ["type": "bye"]
        if let data = try? JSONSerialization.data(withJSONObject: bye) {
            try? await wsTask?.send(.data(data))
        }
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        status = .ended
        lastFrameHash = nil
        transcript = []
        startTime = nil

        ScreenShareManager.shared.stopSharing()
        AgentRegistry.shared.removeAgent(id: "pair")
        AgentRegistry.shared.pushNotification(agent: "Pair", message: "Session ended", state: .done)
    }
}
