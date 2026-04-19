import SwiftUI

/// Top-level SwiftUI view inside the panel. Responsible for:
/// - Rendering the black rounded-bottom notch shape.
/// - Showing collapsed vs expanded content.
/// - Wiring hover and drop events back to the controller.
struct NotchRootView: View {
    @Bindable var controller: NotchController
    @Bindable private var status = AgentStatus.shared

    var body: some View {
        ZStack {
            // The notch "body": black, rounded only at the bottom.
            NotchShape(bottomCornerRadius: 12)
                .fill(.black)

            // Content overlay: changes with state.
            Group {
                switch controller.state {
                case .collapsed:
                    collapsedContent
                case .expanded:
                    expandedContent
                }
            }
        }
        // Entire panel surface responds to hover and drop.
        .trackHover { hovering in
            if hovering {
                controller.hoverBegan()
            } else {
                controller.hoverEnded()
            }
        }
        .receiveDroppedFile { url in
            controller.didReceiveDrop(url)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.1)
                                : .spring(response: 0.4, dampingFraction: 0.75),
                   value: controller.state)
    }

    // MARK: - Content

    private var collapsedContent: some View {
        // A thin status dot inside the notch gives a glanceable signal
        // even when nothing is hovered. Keep it subtle.
        HStack {
            Spacer()
            Circle()
                .fill(status.state.color.opacity(status.state == .idle ? 0 : 0.9))
                .frame(width: 6, height: 6)
                .padding(.trailing, 8)
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HeklaStatusView(status: status)
            if let drop = controller.lastDroppedFile {
                Divider().overlay(.white.opacity(0.08))
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
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
/// Matches the visual affordance of the physical display notch extending downward.
struct NotchShape: Shape {
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = bottomCornerRadius
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
