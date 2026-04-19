import SwiftUI

struct NotchRootView: View {
    @Bindable var controller: NotchController
    @Bindable private var registry = AgentRegistry.shared

    @State private var dropTargeted = false
    @State private var dropFlash = false

    private let cornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            NotchShape(bottomCornerRadius: cornerRadius)
                .fill(.black)

            // Drop flash
            if dropFlash {
                NotchShape(bottomCornerRadius: cornerRadius)
                    .fill(.blue.opacity(0.1))
                    .transition(.opacity)
            }

            // Content
            Group {
                switch controller.state {
                case .collapsed:
                    collapsedContent
                        .transition(.opacity)
                case .expanded:
                    expandedContent
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }

            // Drop targeting — cards breathe
            if dropTargeted {
                NotchShape(bottomCornerRadius: cornerRadius)
                    .fill(.blue.opacity(0.05))
                    .transition(.opacity)
            }
        }
        .trackHover { hovering in
            if hovering {
                controller.hoverBegan()
            } else {
                controller.hoverEnded()
            }
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
        // No broad .animation modifier — transitions handle expand/collapse,
        // and explicit withAnimation calls handle drop/targeting.
    }

    private func triggerDropFlash() {
        withAnimation(.easeIn(duration: 0.1)) { dropFlash = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) { dropFlash = false }
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(registry.summaryState.color)
                .opacity(registry.summaryState == .idle ? 0 : 1)
                .frame(width: 6, height: 6)
                .shadow(color: registry.summaryState.color.opacity(0.5), radius: 3)
                .padding(.trailing, 10)
        }
        .padding(.top, 8)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)

            HStack(spacing: 6) {
                ForEach(registry.agents) { agent in
                    AgentCard(status: agent)
                }

                if let drop = controller.lastDroppedFile {
                    DropCard(url: drop)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity)
                                    .combined(with: .offset(x: 20)),
                                removal: .opacity
                            )
                        )
                }
            }
            .padding(.horizontal, 12)
            .scaleEffect(dropTargeted ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: dropTargeted)

            Spacer(minLength: 0)
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - Cards

struct AgentCard: View {
    @Bindable var status: AgentStatus

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if status.state != .idle {
                    Circle()
                        .fill(status.state.color.opacity(0.25))
                        .frame(width: 14, height: 14)
                        .blur(radius: 4)
                }

                Circle()
                    .fill(status.state.color)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.agent)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Text(status.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if status.state == .attention {
                Text("!")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 14, height: 14)
                    .background(status.state.color, in: Circle())
                    .transition(.scale.combined(with: .opacity))
            } else if status.state == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.07))
        )
    }
}

struct DropCard: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Context")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.blue.opacity(0.1))
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
