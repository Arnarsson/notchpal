import Foundation

/// Discovers API endpoints dynamically from OpenAPI spec.
/// No hardcoded paths — everything resolved at runtime.
@Observable
final class EndpointResolver {
    static let shared = EndpointResolver()

    var discoveredAt: Date?
    var lastError: String?
    var isDiscovered: Bool { discoveredAt != nil }

    /// Resolved endpoints per capability
    private(set) var endpoints: [Capability: ResolvedEndpoint] = [:]

    enum Capability: String, CaseIterable {
        case health
        case dashboard
        case tasks
        case decisions
        case command
        case comms
    }

    struct ResolvedEndpoint: CustomStringConvertible {
        let path: String
        let method: String  // GET, POST, etc.
        var description: String { "\(method) \(path)" }
    }

    /// All discovered paths from OpenAPI
    private var allPaths: [(path: String, methods: [String])] = []

    private init() {}

    // MARK: - Discovery

    /// Fetch /openapi.json and build the endpoint map.
    func discover(baseURL: String) async {
        let candidates = ["/openapi.json", "/docs/openapi.json", "/api/openapi.json", "/openapi"]

        for candidate in candidates {
            guard let url = URL(string: "\(baseURL)\(candidate)") else { continue }
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 8
                let session = URLSession(configuration: config)
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

                if try parseOpenAPI(data) {
                    resolveCapabilities()
                    discoveredAt = Date()
                    lastError = nil
                    return
                }
            } catch {
                continue
            }
        }

        // Fallback: try to probe known path patterns
        await probeEndpoints(baseURL: baseURL)
    }

    /// Parse OpenAPI JSON and extract all paths with their methods.
    private func parseOpenAPI(_ data: Data) throws -> Bool {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["paths"] as? [String: Any] else {
            return false
        }

        allPaths = paths.compactMap { (path, value) in
            guard let methods = value as? [String: Any] else { return nil }
            return (path: path, methods: Array(methods.keys))
        }

        return !allPaths.isEmpty
    }

    /// Probe common paths to discover what exists without OpenAPI spec.
    private func probeEndpoints(baseURL: String) async {
        let probePaths = [
            "/health/", "/health/ready",
            "/api/dashboard", "/api/v2/dashboard", "/api/v2/dashboard/stats",
            "/api/tasks", "/api/v2/tasks", "/api/bridge/tasks",
            "/api/decisions", "/api/v2/decisions", "/api/email/decisions",
            "/api/v2/command", "/api/command",
            "/api/communications", "/api/v2/comms/summary", "/api/unified_inbox",
        ]

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)

        var found: [(path: String, methods: [String])] = []

        await withTaskGroup(of: (String, Bool).self) { group in
            for path in probePaths {
                group.addTask {
                    guard let url = URL(string: "\(baseURL)\(path)") else { return (path, false) }
                    do {
                        let (_, response) = try await session.data(from: url)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        return (path, code >= 200 && code < 500) // Even 404 means server is there
                    } catch {
                        return (path, false)
                    }
                }
            }

            for await (path, exists) in group {
                if exists {
                    found.append((path: path, methods: ["GET"]))
                }
            }
        }

        if !found.isEmpty {
            allPaths = found
            resolveCapabilities()
            discoveredAt = Date()
            lastError = nil
        } else {
            lastError = "Bridge unreachable — no endpoints found"
        }
    }

    // MARK: - Resolution

    /// Match discovered paths to capabilities using keyword matching.
    private func resolveCapabilities() {
        endpoints = [:]

        for cap in Capability.allCases {
            let keywords: [String]
            let preferMethod: String

            switch cap {
            case .health:
                keywords = ["health"]
                preferMethod = "GET"
            case .dashboard:
                keywords = ["dashboard", "activity/summary", "stats"]
                preferMethod = "GET"
            case .tasks:
                keywords = ["tasks", "issues", "daily3"]
                preferMethod = "GET"
            case .decisions:
                keywords = ["decisions", "suggestions"]
                preferMethod = "GET"
            case .command:
                keywords = ["command", "catchup", "spawn"]
                preferMethod = "POST"
            case .comms:
                keywords = ["communications", "unified_inbox", "inbox", "comms", "email/messages", "focus-inbox"]
                preferMethod = "GET"
            }

            // Find all matching paths (case-insensitive)
            let matches = allPaths.filter { entry in
                let lower = entry.path.lowercased()
                return keywords.contains { lower.contains($0) }
            }

            // Prefer: correct method > shortest path
            let sorted = matches.sorted { a, b in
                let aHasMethod = a.methods.contains { $0.uppercased() == preferMethod }
                let bHasMethod = b.methods.contains { $0.uppercased() == preferMethod }
                if aHasMethod != bHasMethod { return aHasMethod }
                return a.path.count < b.path.count
            }

            if let best = sorted.first {
                endpoints[cap] = ResolvedEndpoint(
                    path: best.path,
                    method: best.methods.contains(where: { $0.uppercased() == preferMethod }) ? preferMethod : best.methods.first?.uppercased() ?? "GET"
                )
            }
        }
    }

    // MARK: - Lookup

    /// Get the resolved URL for a capability, or nil if not discovered.
    func url(for capability: Capability, baseURL: String) -> URL? {
        guard let endpoint = endpoints[capability] else { return nil }
        return URL(string: "\(baseURL)\(endpoint.path)")
    }

    func method(for capability: Capability) -> String {
        endpoints[capability]?.method ?? "GET"
    }

    /// Debug summary for the debug panel.
    var debugSummary: String {
        var lines: [String] = []
        if let d = discoveredAt {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            lines.append("Discovered: \(fmt.string(from: d))")
        } else {
            lines.append("Not discovered")
        }
        if let err = lastError {
            lines.append("Error: \(err)")
        }
        for cap in Capability.allCases {
            if let ep = endpoints[cap] {
                lines.append("\(cap.rawValue): \(ep)")
            } else {
                lines.append("\(cap.rawValue): —")
            }
        }
        return lines.joined(separator: "\n")
    }
}
