import SwiftUI

struct AgentDetailView: View {
    @Bindable var agent: AgentStatus
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                        Text("AGENTS").font(.system(size: 8, weight: .medium, design: .monospaced)).kerning(1)
                    }
                    .foregroundStyle(Hekla.dim)
                }
                .buttonStyle(.plain)

                Image(systemName: agent.icon).font(.system(size: 10)).foregroundStyle(agent.state.color)
                Text(agent.agent).font(.system(size: 11, weight: .semibold)).foregroundStyle(Hekla.cream)
                Spacer()

                if let ep = agent.sourceEndpoint {
                    Text(ep).font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                switch agent.id {
                case "email": LiveEmailView()
                case "calendar": LiveCalendarView()
                case "issues": LiveIssuesView()
                case "insights": LiveInsightsView()
                case "activity": LiveActivityView()
                case "screenshare": ScreenShareDetailContent()
                case "bridge": BridgeDebugContent()
                default: LiveGenericView(agent: agent)
                }
            }
            .padding(.horizontal, 14)

            // Footer: source + timestamp
            if agent.lastUpdated != nil {
                HStack {
                    Text(agent.lastUpdatedText)
                        .font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim.opacity(0.5))
                    if agent.isStale {
                        Text("STALE").font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Hekla.yellow, in: RoundedRectangle(cornerRadius: 2))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
        }
    }
}

// MARK: - Live Email View (fetches /api/email/messages)

struct LiveEmailView: View {
    @State private var emails: [[String: Any]] = []
    @State private var counts: [String: Int] = [:]
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !counts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(counts.keys.sorted()), id: \.self) { cat in
                        HStack(spacing: 3) {
                            Text("\(counts[cat] ?? 0)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(cat == "priority" ? Hekla.orange : Hekla.cream)
                            Text(cat).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 4)
            }

            if emails.isEmpty && loaded {
                Text("No emails").font(.system(size: 10)).foregroundStyle(Hekla.dim)
            }

            ForEach(Array(emails.prefix(8).enumerated()), id: \.offset) { _, email in
                emailRow(email)
            }
        }
        .task { await fetchEmails() }
    }

    private func emailRow(_ e: [String: Any]) -> some View {
        let from = e["from_name"] as? String ?? e["from_address"] as? String ?? "?"
        let subject = e["subject"] as? String ?? "?"
        let snippet = e["snippet"] as? String ?? ""
        let date = (e["date_sent"] as? String ?? "").prefix(10)
        let category = e["category"] as? String ?? ""
        let unread = e["is_unread"] as? Bool ?? false
        let initial = String(from.prefix(1)).uppercased()

        return HStack(alignment: .top, spacing: 8) {
            Text(initial)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(category == "priority" ? Hekla.cream : Hekla.dim)
                .frame(width: 18, height: 18)
                .background(category == "priority" ? Hekla.orange.opacity(0.2) : Hekla.cardHi, in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(from).font(.system(size: 9, weight: unread ? .semibold : .regular)).foregroundStyle(Hekla.cream).lineLimit(1)
                    Spacer()
                    Text(String(date)).font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim)
                }
                Text(subject).font(.system(size: 9, weight: .medium)).foregroundStyle(Hekla.body).lineLimit(1)
                Text(snippet.replacingOccurrences(of: "&#39;", with: "'").prefix(80))
                    .font(.system(size: 8)).foregroundStyle(Hekla.dim).lineLimit(1)
                Text(category.uppercased())
                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(category == "priority" ? Hekla.orange : Hekla.dim)
                    .kerning(0.5)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Hekla.card))
    }

    private func fetchEmails() async {
        let base = EurekaBridge.shared.baseURL
        // Counts
        if let url = URL(string: "\(base)/api/email/categories/counts"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cats = json["categories"] as? [[String: Any]] {
            counts = Dictionary(uniqueKeysWithValues: cats.compactMap {
                guard let name = $0["name"] as? String, let unread = $0["unread"] as? Int else { return nil }
                return (name, unread)
            })
        }
        // Messages
        if let url = URL(string: "\(base)/api/email/messages"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msgs = json["messages"] as? [[String: Any]] {
            emails = msgs
        }
        loaded = true
    }
}

// MARK: - Live Calendar View

struct LiveCalendarView: View {
    @State private var events: [[String: Any]] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if events.isEmpty && loaded {
                Text("No upcoming events").font(.system(size: 10)).foregroundStyle(Hekla.dim)
            }
            ForEach(Array(events.prefix(6).enumerated()), id: \.offset) { _, event in
                let summary = event["summary"] as? String ?? "?"
                let start = (event["start"] as? String ?? "").prefix(16)
                let end = (event["end"] as? String ?? "").prefix(16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary).font(.system(size: 10, weight: .semibold)).foregroundStyle(Hekla.cream)
                    Text("\(start) → \(end.suffix(5))")
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Hekla.card))
            }
        }
        .task { await fetchEvents() }
    }

    private func fetchEvents() async {
        let base = EurekaBridge.shared.baseURL
        if let url = URL(string: "\(base)/api/calendar/events/upcoming"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let evts = json["events"] as? [[String: Any]] {
            events = evts
        }
        loaded = true
    }
}

// MARK: - Live Issues View

struct LiveIssuesView: View {
    @State private var issues: [[String: Any]] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if issues.isEmpty && loaded {
                Text("No issues").font(.system(size: 10)).foregroundStyle(Hekla.dim)
            }
            ForEach(Array(issues.prefix(10).enumerated()), id: \.offset) { _, issue in
                let title = issue["title"] as? String ?? issue["name"] as? String ?? "?"
                let status = issue["status"] as? String ?? "?"

                HStack(spacing: 6) {
                    Circle()
                        .fill(status == "todo" ? Hekla.orange : (status == "backlog" ? Hekla.dim : Hekla.green))
                        .frame(width: 5, height: 5)
                    Text(title).font(.system(size: 9)).foregroundStyle(Hekla.cream).lineLimit(1)
                    Spacer()
                    Text(status.uppercased())
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Hekla.dim).kerning(0.5)
                }
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Hekla.card))
            }
        }
        .task { await fetchIssues() }
    }

    private func fetchIssues() async {
        let base = EurekaBridge.shared.baseURL
        if let url = URL(string: "\(base)/api/issues"),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                issues = arr
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["issues"] as? [[String: Any]] {
                issues = items
            }
        }
        loaded = true
    }
}

// MARK: - Live Insights View

struct LiveInsightsView: View {
    @State private var actions: [[String: Any]] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if actions.isEmpty && loaded {
                Text("Nothing flagged").font(.system(size: 10)).foregroundStyle(Hekla.dim)
            }
            ForEach(Array(actions.prefix(8).enumerated()), id: \.offset) { _, action in
                let title = (action["title"] as? String ?? "?").replacingOccurrences(of: "Escalate: ", with: "")
                let desc = action["description"] as? String ?? ""
                let priority = action["priority"] as? String ?? "?"

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(Hekla.cream).lineLimit(1)
                        Spacer()
                        Text(priority.uppercased())
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(priority == "high" ? Hekla.orange : Hekla.dim)
                            .kerning(0.5)
                    }
                    Text(desc).font(.system(size: 8)).foregroundStyle(Hekla.dim).lineLimit(1)
                }
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Hekla.card))
            }
        }
        .task { await fetchInsights() }
    }

    private func fetchInsights() async {
        let base = EurekaBridge.shared.baseURL
        if let url = URL(string: "\(base)/api/insights/suggested-actions"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = json["actions"] as? [[String: Any]] {
            actions = items
        }
        loaded = true
    }
}

// MARK: - Live Activity View

struct LiveActivityView: View {
    @State private var hours: [[String: Any]] = []
    @State private var totalCaptures = 0
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if totalCaptures > 0 {
                Text("\(totalCaptures) captures today")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Hekla.cream)
                    .padding(.bottom, 2)
            }
            ForEach(Array(hours.suffix(8).reversed().enumerated()), id: \.offset) { _, hour in
                let h = hour["hour"] as? Int ?? 0
                let count = hour["capture_count"] as? Int ?? 0
                let summary = hour["summary"] as? String ?? ""
                let apps = (hour["apps"] as? [String])?.joined(separator: ", ") ?? ""

                HStack(spacing: 6) {
                    Text(String(format: "%02d:00", h))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                        .frame(width: 32, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.isEmpty ? apps : summary)
                            .font(.system(size: 9)).foregroundStyle(Hekla.body).lineLimit(1)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange)
                }
                .padding(.vertical, 2)
            }
        }
        .task { await fetchActivity() }
    }

    private func fetchActivity() async {
        let base = EurekaBridge.shared.baseURL
        if let url = URL(string: "\(base)/api/activity/summary"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            totalCaptures = json["total_captures"] as? Int ?? 0
            hours = json["hours"] as? [[String: Any]] ?? []
        }
        loaded = true
    }
}

// MARK: - Generic fallback

struct LiveGenericView: View {
    @Bindable var agent: AgentStatus
    @State private var rawData: [String: Any]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoCard {
                row("State", agent.state.statusLabel)
                row("Info", agent.label)
                if let ep = agent.sourceEndpoint { row("Source", ep) }
            }
            if let data = rawData {
                infoCard {
                    ForEach(Array(data.keys.sorted().prefix(10)), id: \.self) { key in
                        row(key, stringVal(data[key]))
                    }
                }
            }
        }
        .task {
            guard let ep = agent.sourceEndpoint,
                  let url = URL(string: "\(EurekaBridge.shared.baseURL)\(ep)"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            rawData = json
        }
    }

    private func infoCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) { content() }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }
    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
            Spacer()
            Text(v).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.cream).lineLimit(1)
        }
    }
    private func stringVal(_ v: Any?) -> String {
        switch v {
        case let s as String: return s.count > 50 ? String(s.prefix(50)) + "…" : s
        case let n as Int: return "\(n)"
        case let b as Bool: return b ? "true" : "false"
        case let a as [Any]: return "[\(a.count)]"
        case let d as [String: Any]: return "{\(d.count)}"
        default: return "—"
        }
    }
}

// MARK: - Bridge Debug

struct BridgeDebugContent: View {
    @Bindable var bridge = EurekaBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            card("CONNECTION") {
                row("URL", bridge.baseURL)
                row("Status", bridge.isConnected ? "Connected" : "Offline")
                row("AI", bridge.aiOnline ? "Online" : "Credits exhausted")
                if let err = bridge.error { row("Error", err) }
            }
            card("CHAT ENDPOINT") {
                if let ep = bridge.chatEndpoint {
                    row("Found", "POST \(ep)")
                } else {
                    Text("No direct chat endpoint found").font(.system(size: 9)).foregroundStyle(Color(hex: 0xFF5F57))
                }
            }
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)
            content()
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }
    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
            Spacer()
            Text(v).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.cream).lineLimit(1)
        }
    }
}

// MARK: - Screen Share

struct ScreenShareDetailContent: View {
    @Bindable var manager = ScreenShareManager.shared

    var body: some View {
        VStack(spacing: 10) {
            if manager.isSharing {
                if let frame = manager.latestFrame {
                    Image(nsImage: frame)
                        .resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule()).padding(6)
                        }
                }
                Button {
                    manager.stopSharing()
                    if let a = AgentRegistry.shared.agent(id: "screenshare") { a.state = .idle; a.label = "Not sharing" }
                } label: {
                    Text("STOP SHARING").font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).kerning(1).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled").font(.system(size: 28)).foregroundStyle(Hekla.dim)
                    Text("Share your screen with Eureka").font(.system(size: 11)).foregroundStyle(Hekla.body)
                    Text("1 FPS · No audio · Stays on device").font(.system(size: 9)).foregroundStyle(Hekla.dim)
                    Button {
                        Task {
                            await manager.startSharing()
                            if let a = AgentRegistry.shared.agent(id: "screenshare") { a.state = .busy; a.label = "Sharing · 960×540" }
                        }
                    } label: {
                        Text("START SHARING").font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white).kerning(1).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Hekla.orange, in: RoundedRectangle(cornerRadius: 4))
                    }.buttonStyle(.plain)
                }.padding(.vertical, 8)
            }
        }
    }
}
