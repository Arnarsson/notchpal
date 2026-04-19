import SwiftUI

enum Hekla {
    // Appearance-adaptive: dark mode uses volcanic palette, light mode inverts
    static let bg      = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.075, green: 0.067, blue: 0.063, alpha: 1) : NSColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1) })
    static let card    = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.118, green: 0.114, blue: 0.106, alpha: 1) : NSColor(red: 1, green: 1, blue: 1, alpha: 1) })
    static let cardHi  = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.165, green: 0.157, blue: 0.149, alpha: 1) : NSColor(red: 0.9, green: 0.89, blue: 0.87, alpha: 1) })
    static let cream   = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.941, green: 0.902, blue: 0.827, alpha: 1) : NSColor(red: 0.1, green: 0.09, blue: 0.08, alpha: 1) })
    static let body    = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.722, green: 0.686, blue: 0.635, alpha: 1) : NSColor(red: 0.35, green: 0.33, blue: 0.3, alpha: 1) })
    static let dim     = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(red: 0.502, green: 0.478, blue: 0.447, alpha: 1) : NSColor(red: 0.6, green: 0.58, blue: 0.55, alpha: 1) })
    static let orange  = Color(hex: 0xD4643A)  // accent stays constant
    static let green   = Color(hex: 0x28C840)
    static let yellow  = Color(hex: 0xFEBC2E)
}

struct NotchRootView: View {
    @Bindable var controller: NotchController
    @Bindable private var registry = AgentRegistry.shared

    @State private var dropTargeted = false
    @State private var dropFlash = false
    @State private var showAskInput = false
    @State private var askText = ""
    @State private var askResponse: String?

    private let cornerRadius: CGFloat = 22

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomCornerRadius: cornerRadius)
                .fill(.black)

            if dropFlash {
                NotchShape(bottomCornerRadius: cornerRadius)
                    .fill(Hekla.orange.opacity(0.08))
                    .transition(.opacity)
            }

            Group {
                switch controller.state {
                case .collapsed:
                    collapsedContent.transition(.opacity)
                case .expanded:
                    if let agent = controller.selectedAgent {
                        AgentDetailView(agent: agent, onBack: { controller.deselectAgent() })
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if controller.showHistory {
                        historyContent
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if controller.showDropSuggestions, let url = controller.lastDroppedFile {
                        dropSuggestionsContent(url)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        listContent
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.selectedAgent?.id)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.showHistory)

            if dropTargeted {
                NotchShape(bottomCornerRadius: cornerRadius)
                    .fill(Hekla.orange.opacity(0.04))
                    .transition(.opacity)
            }

            // HUD notifications
            if controller.state == .collapsed {
                VStack(spacing: 4) {
                    ForEach(registry.notifications) { notif in
                        HUDPill(notification: notif)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 36)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: registry.notifications.count)
            }
        }
        .trackHover { hovering in
            if hovering { controller.hoverBegan() } else { controller.hoverEnded() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            if !providers.isEmpty { controller.hoverBegan() }
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    controller.didReceiveDrop(url)
                    triggerDropFlash()
                }
            }
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            if targeted { controller.hoverBegan() }
        }
    }

    private func triggerDropFlash() {
        withAnimation(.easeIn(duration: 0.1)) { dropFlash = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) { dropFlash = false }
    }

    // MARK: - Compact State (flanking data points)

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // Left: highest priority data point
            compactLeft
                .padding(.leading, 8)

            Spacer()

            // Center dot
            Circle()
                .fill(registry.summaryState.color)
                .opacity(registry.summaryState == .idle ? 0 : 1)
                .frame(width: 5, height: 5)
                .shadow(color: registry.summaryState.color.opacity(0.5), radius: 3)

            Spacer()

            // Right: second priority data point
            compactRight
                .padding(.trailing, 8)
        }
        .padding(.top, 6)
    }

    private var compactLeft: some View {
        Group {
            if bridge.activeWorkerCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 7)).foregroundStyle(Hekla.orange)
                    Text("AI").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Hekla.cream)
                }
            } else if bridge.priorityEmailCount > 0 {
                HStack(spacing: 3) {
                    Text("\(bridge.priorityEmailCount)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Hekla.orange)
                    Image(systemName: "envelope.fill").font(.system(size: 7)).foregroundStyle(Hekla.dim)
                }
            } else if let event = bridge.nextEventName {
                Text(String(event.prefix(8)))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Hekla.dim)
            } else {
                EmptyView()
            }
        }
    }

    private var compactRight: some View {
        Group {
            if bridge.stuckIssueCount > 0 {
                HStack(spacing: 3) {
                    Text("\(bridge.stuckIssueCount)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Hekla.yellow)
                    Text("stuck").font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim)
                }
            } else if let time = bridge.nextEventTime {
                Text(time).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Hekla.dim)
            } else if bridge.isConnected {
                Circle().fill(Hekla.green).frame(width: 4, height: 4)
            } else {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 4, height: 4)
            }
        }
    }

    @State private var showAllAgents = false

    // MARK: - Expanded: Prioritized Feed

    private var listContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            // Header: EUREKA + quick actions
            HStack(spacing: 8) {
                Text("EUREKA")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Hekla.orange)
                    .kerning(2)

                Spacer()

                // Pair button (feature-flagged)
                if PairSession.isEnabled {
                    Button {
                        if PairSession.shared.status == .idle || PairSession.shared.status == .ended {
                            Task { await PairSession.shared.start() }
                            controller.selectAgent(AgentRegistry.shared.agent(id: "pair") ?? AgentStatus(id: "pair", agent: "Pair"))
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Circle().fill(PairSession.shared.status == .live ? Hekla.green : Hekla.dim).frame(width: 4, height: 4)
                            Text(PairSession.shared.status == .live ? PairSession.shared.elapsed : "Pair")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Hekla.cream)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(PairSession.shared.status == .live ? Hekla.green.opacity(0.15) : Hekla.cardHi, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!OpenClawBridge.shared.isAvailable && PairSession.shared.status == .idle)
                }

                // Quick action icons
                quickAction("bolt.fill") { Task { await bridge.spawnWorker() } }
                quickAction("envelope.arrow.triangle.branch") { Task { await bridge.syncEmail() } }
                quickAction("archivebox") { Task { await bridge.archiveNewsletters() } }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showAskInput.toggle()
                        if !showAskInput { askText = ""; askResponse = nil }
                    }
                } label: {
                    Image(systemName: showAskInput ? "xmark" : "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(Hekla.cream)
                        .frame(width: 22, height: 22)
                        .background(showAskInput ? Hekla.orange.opacity(0.3) : Hekla.cardHi, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            // Inline ask
            if showAskInput {
                inlineAskView
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Prioritized cards — max 4, scored by importance
            let scored = prioritizedAgents
            VStack(spacing: 5) {
                ForEach(scored.prefix(showAllAgents ? 20 : 4)) { agent in
                    AgentCard(status: agent, compact: false, focused: false)
                        .onTapGesture { controller.selectAgent(agent) }
                }
            }
            .padding(.horizontal, 12)
            .scaleEffect(dropTargeted ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: dropTargeted)

            // See all / collapse toggle
            if registry.agents.count > 4 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showAllAgents.toggle()
                    }
                    controller.resizePanel()
                } label: {
                    Text(showAllAgents ? "Show less" : "See all \(registry.agents.count) agents")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Hekla.dim)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            bottomBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    /// Sort agents by priority score — attention > busy > others
    private var prioritizedAgents: [AgentStatus] {
        registry.agents.sorted { a, b in
            priorityScore(a) > priorityScore(b)
        }
    }

    private func priorityScore(_ agent: AgentStatus) -> Int {
        switch agent.state {
        case .error: return 100
        case .attention: return 90
        case .busy: return 70
        case .done: return 30
        case .idle: return 10
        }
    }

    private func quickAction(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Hekla.dim)
                .frame(width: 22, height: 22)
                .background(Hekla.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Hekla.cardHi.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drop suggestions

    private func dropSuggestionsContent(_ url: URL) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)

            HStack(spacing: 8) {
                Image(systemName: "doc.fill").font(.system(size: 11)).foregroundStyle(Hekla.orange)
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Hekla.cream)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    controller.dismissDropSuggestions()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Hekla.dim)
                        .frame(width: 16, height: 16)
                        .background(Hekla.cardHi, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                ForEach(registry.dropSuggestions) { suggestion in
                    Button {
                        AgentRegistry.shared.pushNotification(
                            agent: suggestion.agentName,
                            message: "\(suggestion.action): \(url.lastPathComponent)",
                            state: .busy
                        )
                        controller.dismissDropSuggestions()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(Hekla.orange)
                            Text(suggestion.action)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Hekla.cream)
                            Text(suggestion.agentName)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Hekla.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Hekla.card)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Hekla.cardHi.opacity(0.4), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Notification history

    private var historyContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)

            HStack {
                Text("NOTIFICATION HISTORY")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Hekla.orange)
                    .kerning(1.5)
                Spacer()
                Button { controller.toggleHistory() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Hekla.dim)
                        .frame(width: 16, height: 16)
                        .background(Hekla.cardHi, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(registry.notificationHistory.prefix(20).enumerated()), id: \.element.id) { idx, notif in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(notif.state.color)
                                .frame(width: 5, height: 5)
                            Text(notif.agent.uppercased())
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Hekla.cream)
                                .kerning(0.8)
                                .frame(width: 70, alignment: .leading)
                            Text(notif.message)
                                .font(.system(size: 9))
                                .foregroundStyle(Hekla.dim)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(idx % 2 == 0 ? Hekla.card.opacity(0.5) : Color.clear)
                    }
                }
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Inline ask

    private var inlineAskView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Hekla.dim)

                TextField("Ask Eureka…", text: $askText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Hekla.cream)
                    .onSubmit { submitAsk() }

                if !askText.isEmpty {
                    Button {
                        submitAsk()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Hekla.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Hekla.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Hekla.cardHi, lineWidth: 0.5)))

            if let response = askResponse {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(Hekla.orange).frame(width: 4, height: 4).padding(.top, 4)
                    Text(response)
                        .font(.system(size: 10))
                        .foregroundStyle(Hekla.body)
                        .lineLimit(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Hekla.card))
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private func submitAsk() {
        guard !askText.isEmpty else { return }
        let question = askText
        askText = ""

        let ebridge = EurekaBridge.shared
        if ebridge.isConnected || OpenClawBridge.shared.isAvailable {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                askResponse = "Thinking…"
            }
            Task {
                if let response = await ebridge.sendCommandRouted(question) {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            askResponse = response
                        }
                    }
                } else {
                    await MainActor.run {
                        withAnimation { askResponse = "No response from Eureka." }
                    }
                }
                AgentRegistry.shared.pushNotification(agent: "Eureka", message: "Answered: \(question)", state: .done)
            }
        } else {
            // Offline fallback
            let responses = [
                "Eureka is offline. Connect to 100.83.83.58 to use real commands.",
                "Can't reach the API. Is the Linux box running?",
            ]
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                askResponse = responses[abs(question.hashValue) % responses.count]
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var statusSummary: some View {
        let w = registry.workingCount
        let n = registry.needsYouCount
        HStack(spacing: 0) {
            if w > 0 {
                Text("  \(w) running")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Hekla.dim)
            }
            if n > 0 {
                Text(" · ").font(.system(size: 9, design: .monospaced)).foregroundStyle(Hekla.dim)
                Text("\(n) need you")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Hekla.yellow)
            }
        }
    }

    @Bindable private var bridge = EurekaBridge.shared

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text("EUREKA")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Hekla.dim)
                .kerning(0.5)
            Spacer()

            // History button
            Button { controller.toggleHistory() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 8))
                    if !registry.notificationHistory.isEmpty {
                        Text("\(registry.notificationHistory.count)")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundStyle(Hekla.dim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Hekla.cardHi.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)

            // No mock service checks — only real Eureka status
            HStack(spacing: 2) {
                Text("Eureka").font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                Text(bridge.isConnected ? "✓" : "✗").font(.system(size: 8))
                    .foregroundStyle(bridge.isConnected ? Hekla.green : Color(hex: 0xFF5F57))
            }
            .padding(.leading, 6)
            // OpenClaw status
            HStack(spacing: 2) {
                Text("◆").font(.system(size: 6)).foregroundStyle(OpenClawBridge.shared.isAvailable ? Hekla.green : Hekla.dim)
                Text("OC").font(.system(size: 7, design: .monospaced)).foregroundStyle(Hekla.dim)
            }
            .padding(.leading, 6)

            if !bridge.aiOnline {
                Text("AI offline")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xFF5F57))
                    .padding(.leading, 6)
            }
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - HUD Pill

struct HUDPill: View {
    let notification: HUDNotification

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(notification.state.color)
                .frame(width: 6, height: 6)
                .shadow(color: notification.state.color.opacity(0.5), radius: 3)
            Text(notification.agent.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Hekla.cream)
                .kerning(1)
            Text(notification.message)
                .font(.system(size: 10))
                .foregroundStyle(Hekla.body)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Hekla.card)
                .overlay(Capsule().stroke(Hekla.cardHi, lineWidth: 0.5))
        )
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    @Bindable var status: AgentStatus
    var compact: Bool = false
    var focused: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            // Agent icon with status color
            ZStack {
                if status.state != .idle && status.state != .done {
                    Circle()
                        .fill(status.state.color.opacity(0.15))
                        .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                }
                Image(systemName: status.icon)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(status.state == .idle ? Hekla.dim : status.state.color)
            }
            .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)

            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                HStack(spacing: 6) {
                    Text(status.agent)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(Hekla.cream)
                        .lineLimit(1)

                    if let progress = status.progress, !compact {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Hekla.orange)
                    }
                }
                HStack(spacing: 4) {
                    Text(status.label)
                        .font(.system(size: compact ? 8 : 9))
                        .foregroundStyle(Hekla.dim)
                        .lineLimit(1)
                    if !compact, status.lastUpdated != nil {
                        Text("· \(status.lastUpdatedText)")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Hekla.dim.opacity(0.6))
                    }
                    if status.isStale {
                        Text("STALE")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Hekla.yellow, in: RoundedRectangle(cornerRadius: 2))
                    }
                }
            }

            Spacer(minLength: 0)

            if status.state == .attention {
                Circle()
                    .fill(Hekla.yellow)
                    .frame(width: compact ? 12 : 16, height: compact ? 12 : 16)
                    .overlay(
                        Text("!")
                            .font(.system(size: compact ? 7 : 9, weight: .heavy))
                            .foregroundStyle(.black)
                    )
            }

            // Quick stop for screen share
            if status.id == "screenshare" && ScreenShareManager.shared.isSharing {
                Button {
                    ScreenShareManager.shared.stopSharing()
                    status.state = .idle
                    status.label = "Not sharing"
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Hekla.dim.opacity(0.5))
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status.justCompleted ? Hekla.green.opacity(0.15) : (focused ? Hekla.orange.opacity(0.08) : Hekla.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            focused ? Hekla.orange.opacity(0.5)
                            : status.justCompleted ? Hekla.green.opacity(0.4)
                            : Hekla.cardHi.opacity(0.4),
                            lineWidth: focused ? 1 : 0.5
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: focused)
                .animation(.easeInOut(duration: 0.3), value: status.justCompleted)
        )
        .contentShape(Rectangle())
        .contextMenu {
            if status.state == .busy {
                Button("Pause") {
                    status.state = .idle
                    status.label = "Paused"
                    status.progress = nil
                }
            }
            if status.state == .idle || status.state == .done {
                Button("Restart") {
                    status.state = .busy
                    status.label = "Restarting…"
                    status.progress = 0.0
                }
            }
            if status.state == .attention {
                Button("Approve") {
                    AgentRegistry.shared.approveAgent(id: status.id, action: "send")
                }
                Button("Dismiss") {
                    AgentRegistry.shared.approveAgent(id: status.id, action: "reject")
                }
            }
            Divider()
            Button("Remove") {
                AgentRegistry.shared.removeAgent(id: status.id)
            }
        }
    }
}

// MARK: - Drop Card

struct DropCard: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(Hekla.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Hekla.cream)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Dropped to context")
                    .font(.system(size: 9))
                    .foregroundStyle(Hekla.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Hekla.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Hekla.orange.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - NotchShape

struct NotchShape: Shape, InsettableShape {
    let bottomCornerRadius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.inset = amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = max(bottomCornerRadius - inset, 0)
        let rect = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.closeSubpath()
        return p
    }
}
