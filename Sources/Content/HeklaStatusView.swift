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

                Image(systemName: agent.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(agent.state.color)
                Text(agent.agent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Hekla.cream)

                Spacer()

                Circle().fill(agent.state.color).frame(width: 6, height: 6)
                    .shadow(color: agent.state.color.opacity(0.5), radius: 3)
                Text(agent.state.statusLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(agent.state.color)
                    .kerning(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                switch agent.id {
                case "screenshare": ScreenShareDetailContent()
                case "bridge": BridgeDebugContent()
                default: LiveDataDetailContent(agent: agent)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Live data detail (real API data, no mock)

struct LiveDataDetailContent: View {
    @Bindable var agent: AgentStatus
    @State private var liveData: [String: Any]?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            infoCard("STATUS") {
                row("State", agent.state.statusLabel)
                row("Label", agent.label)
                if let ep = agent.sourceEndpoint {
                    row("Source", ep)
                }
                row("Updated", agent.lastUpdatedText)
                if agent.isStale {
                    HStack {
                        Text("STALE").font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Hekla.yellow, in: RoundedRectangle(cornerRadius: 2))
                        Text("Data older than 7 days")
                            .font(.system(size: 8)).foregroundStyle(Hekla.dim)
                    }
                }
            }

            // Live data from endpoint
            if let ep = agent.sourceEndpoint {
                infoCard("LIVE DATA · \(ep)") {
                    if loading {
                        HStack {
                            ProgressView().scaleEffect(0.5).tint(Hekla.orange)
                            Text("Fetching…").font(.system(size: 9)).foregroundStyle(Hekla.dim)
                        }
                    } else if let data = liveData {
                        ForEach(Array(data.keys.sorted().prefix(12)), id: \.self) { key in
                            let val = stringValue(data[key])
                            row(key, val)
                        }
                    } else {
                        Text("Tap refresh to load")
                            .font(.system(size: 9)).foregroundStyle(Hekla.dim)
                    }
                }

                Button {
                    Task { await fetchLiveData(endpoint: ep) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                        Text("REFRESH").font(.system(size: 8, weight: .medium, design: .monospaced)).kerning(1)
                    }
                    .foregroundStyle(Hekla.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Hekla.cardHi, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            if let ep = agent.sourceEndpoint {
                Task { await fetchLiveData(endpoint: ep) }
            }
        }
    }

    private func fetchLiveData(endpoint: String) async {
        loading = true
        defer { loading = false }
        let base = EurekaBridge.shared.baseURL
        guard let url = URL(string: "\(base)\(endpoint)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                liveData = json
            } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                liveData = ["count": arr.count, "items": arr.prefix(5).map { $0["title"] ?? $0["name"] ?? $0["subject"] ?? "?" }]
            }
        } catch {}
    }

    private func stringValue(_ val: Any?) -> String {
        switch val {
        case let s as String: return s.count > 60 ? String(s.prefix(60)) + "…" : s
        case let n as Int: return "\(n)"
        case let d as Double: return String(format: "%.1f", d)
        case let b as Bool: return b ? "true" : "false"
        case let arr as [Any]: return "[\(arr.count) items]"
        case let dict as [String: Any]: return "{\(dict.count) keys}"
        default: return "null"
        }
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)
            content()
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
            Spacer()
            Text(value).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.cream).lineLimit(1)
        }
    }
}

// MARK: - Bridge Debug

struct BridgeDebugContent: View {
    @Bindable var bridge = EurekaBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoCard("CONNECTION") {
                row("URL", bridge.baseURL)
                row("Status", bridge.isConnected ? "Connected" : "Offline")
                row("AI", bridge.aiOnline ? "Online" : "Credits exhausted")
                if let poll = bridge.lastPoll {
                    let fmt = DateFormatter()
                    let _ = fmt.dateFormat = "HH:mm:ss"
                    row("Last poll", fmt.string(from: poll))
                }
                if let err = bridge.error {
                    row("Error", err)
                }
            }

            infoCard("CHAT ENDPOINT") {
                if let ep = bridge.chatEndpoint {
                    row("Discovered", "POST \(ep)")
                } else {
                    Text("No direct chat endpoint found")
                        .font(.system(size: 9)).foregroundStyle(Color(hex: 0xFF5F57))
                }
            }
        }
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.orange).kerning(1.5)
            content()
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Hekla.card))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
            Spacer()
            Text(value).font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.cream).lineLimit(1)
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
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(6)
                        }
                }

                HStack(spacing: 16) {
                    statBadge("\(manager.frameCount)", "frames")
                    statBadge("960×540", "resolution")
                    Spacer()
                }

                Button {
                    manager.stopSharing()
                    if let a = AgentRegistry.shared.agent(id: "screenshare") {
                        a.state = .idle; a.label = "Not sharing"
                    }
                } label: {
                    Text("STOP SHARING")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).kerning(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 28)).foregroundStyle(Hekla.dim)
                    Text("Share your screen with Eureka")
                        .font(.system(size: 11)).foregroundStyle(Hekla.body)
                    Text("1 FPS · No audio · Stays on device")
                        .font(.system(size: 9)).foregroundStyle(Hekla.dim)

                    Button {
                        Task {
                            await manager.startSharing()
                            if let a = AgentRegistry.shared.agent(id: "screenshare") {
                                a.state = .busy; a.label = "Sharing · 960×540"
                            }
                        }
                    } label: {
                        Text("START SHARING")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white).kerning(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Hekla.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func statBadge(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Hekla.cream)
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
        }
    }
}
