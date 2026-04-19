import SwiftUI

/// Single agent status row in the expanded panel.
struct AgentStatusRow: View {
    @Bindable var status: AgentStatus

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.state.color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(status.agent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(status.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// Multi-agent status list in the expanded panel.
struct HeklaStatusView: View {
    @Bindable var registry: AgentRegistry

    var body: some View {
        VStack(spacing: 0) {
            ForEach(registry.agents) { agent in
                if agent.id != registry.agents.first?.id {
                    Divider()
                        .overlay(.white.opacity(0.06))
                        .padding(.horizontal, 16)
                }
                AgentStatusRow(status: agent)
            }
        }
    }
}
