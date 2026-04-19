import SwiftUI

struct HeklaStatusView: View {
    @Bindable var status: AgentStatus

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.state.color)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(status.agent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
