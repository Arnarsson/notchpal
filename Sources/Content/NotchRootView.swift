import SwiftUI

enum Hekla {
    static let bg      = Color(hex: 0x131110)
    static let card    = Color(hex: 0x1E1D1B)
    static let cardHi  = Color(hex: 0x2A2826)
    static let cream   = Color(hex: 0xF0E6D3)
    static let body    = Color(hex: 0xB8AFA2)
    static let dim     = Color(hex: 0x807A72)
    static let orange  = Color(hex: 0xD4643A)
    static let green   = Color(hex: 0x28C840)
    static let yellow  = Color(hex: 0xFEBC2E)
}

struct NotchRootView: View {
    @Bindable var controller: NotchController
    @Bindable private var registry = AgentRegistry.shared

    @State private var dropTargeted = false
    @State private var dropFlash = false

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

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 4) {
            Spacer()
            ZStack {
                Circle()
                    .fill(registry.summaryState.color)
                    .opacity(registry.summaryState == .idle ? 0 : 1)
                    .frame(width: 6, height: 6)
                    .shadow(color: registry.summaryState.color.opacity(0.5), radius: 3)

                // Attention count badge
                if registry.needsYouCount > 0 {
                    Text("\(registry.needsYouCount)")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 12, height: 12)
                        .background(Hekla.yellow, in: Circle())
                        .offset(x: 8, y: -4)
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.top, 8)
    }

    // MARK: - List (main view)

    private var listContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            // Header
            HStack(alignment: .center) {
                Text("HEKLA")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Hekla.orange)
                    .kerning(2)

                statusSummary
                Spacer()

                HStack(spacing: 4) {
                    Text("+")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text("Ask")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Hekla.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Hekla.cardHi, in: RoundedRectangle(cornerRadius: 4))

                Text("⌘Space")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Hekla.dim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Hekla.card, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Hekla.cardHi, lineWidth: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Smart stacking: active agents on top, idle/done below
            let active = registry.agents.filter { $0.state == .busy || $0.state == .attention || $0.state == .error }
            let passive = registry.agents.filter { $0.state == .idle || $0.state == .done }

            VStack(spacing: 6) {
                // Active agents — full width, prominent
                ForEach(active) { agent in
                    AgentCard(status: agent, compact: false)
                        .onTapGesture { controller.selectAgent(agent) }
                }

                // Passive agents — 2-column grid, compact
                if !passive.isEmpty {
                    let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(passive) { agent in
                            AgentCard(status: agent, compact: true)
                                .onTapGesture { controller.selectAgent(agent) }
                        }
                    }
                }

            }
            .padding(.horizontal, 12)
            .scaleEffect(dropTargeted ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: dropTargeted)

            Spacer(minLength: 4)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
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

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text("Autonomy")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Hekla.dim)
                .kerning(0.5)
            Circle().fill(Hekla.green).frame(width: 4, height: 4).padding(.leading, 4)
            Text("  Guardrails")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Hekla.dim)
            Spacer()
            ForEach(["Ollama", "Gmail", "Telegram"], id: \.self) { service in
                HStack(spacing: 2) {
                    Text(service).font(.system(size: 8, design: .monospaced)).foregroundStyle(Hekla.dim)
                    Text("✓").font(.system(size: 8)).foregroundStyle(Hekla.green)
                }
                .padding(.leading, 8)
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

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            // Dot
            ZStack {
                if status.state != .idle && status.state != .done {
                    Circle()
                        .fill(status.state.color.opacity(0.2))
                        .frame(width: 14, height: 14)
                        .blur(radius: 4)
                }
                Circle()
                    .fill(status.state.color)
                    .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                    .shadow(color: status.state.color.opacity(0.5), radius: 3)
            }
            .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)

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
                Text(status.label)
                    .font(.system(size: compact ? 8 : 9))
                    .foregroundStyle(Hekla.dim)
                    .lineLimit(1)
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

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Hekla.dim.opacity(0.5))
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Hekla.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Hekla.cardHi.opacity(0.4), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
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
