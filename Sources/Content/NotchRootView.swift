import SwiftUI

/// Top-level SwiftUI view inside the panel. Responsible for:
/// - Rendering the black rounded-bottom notch shape.
/// - Showing collapsed vs expanded content.
/// - Wiring hover and drop events back to the controller.
struct NotchRootView: View {
    @Bindable var controller: NotchController
    @Bindable private var registry = AgentRegistry.shared

    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            NotchShape(bottomCornerRadius: 12)
                .fill(.black)

            Group {
                switch controller.state {
                case .collapsed:
                    collapsedContent
                case .expanded:
                    expandedContent
                }
            }

            // Drop zone visual feedback
            if dropTargeted {
                NotchShape(bottomCornerRadius: 12)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
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
                }
            }
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            if targeted { controller.hoverBegan() }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.1)
                                : .spring(response: 0.4, dampingFraction: 0.75),
                   value: controller.state)
    }

    // MARK: - Content

    private var collapsedContent: some View {
        HStack {
            Spacer()
            Circle()
                .fill(registry.summaryState.color.opacity(registry.summaryState == .idle ? 0 : 0.9))
                .frame(width: 6, height: 6)
                .padding(.trailing, 8)
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HeklaStatusView(registry: registry)

            if let drop = controller.lastDroppedFile {
                Divider().overlay(.white.opacity(0.08))
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    Text(drop.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Notch-shaped rectangle: sharp top corners, rounded bottom corners.
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
