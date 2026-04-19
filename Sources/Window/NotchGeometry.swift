import AppKit

enum NotchGeometry {

    private static let collapsedPadding: CGFloat = 20

    static func collapsedSize(for screen: NSScreen) -> CGSize {
        if let notch = physicalNotchRect(in: screen) {
            // Wider than physical notch to fit flanking data points
            return CGSize(width: notch.width + 120, height: notch.height + collapsedPadding)
        }
        return CGSize(width: 300, height: 32 + collapsedPadding)
    }

    /// List view: sized to fit agents. Active agents get full rows (~46pt),
    /// passive agents pair up in 2-col grid (~40pt per row).
    /// Fixed expanded size — one size for all content. SwiftUI ScrollView
    /// handles overflow. No dynamic resizing (causes NSHostingView constraint crashes).
    static let expandedSize = CGSize(width: 560, height: 420)

    static func frame(for state: NotchState, on screen: NSScreen) -> NSRect {
        switch state {
        case .collapsed:
            return centeredTopFrame(size: collapsedSize(for: screen), in: screen)
        case .expanded:
            return centeredTopFrame(size: expandedSize, in: screen)
        }
    }

    static func physicalNotchRect(in screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let notchLeft = left.maxX
        let notchRight = right.minX
        guard notchRight > notchLeft else { return nil }
        let width = notchRight - notchLeft
        let height = left.height
        let y = screen.frame.maxY - height
        return NSRect(x: notchLeft, y: y, width: width, height: height)
    }

    private static func centeredTopFrame(size: CGSize, in screen: NSScreen) -> NSRect {
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        return NSRect(origin: origin, size: size)
    }
}

enum NotchState: Equatable {
    case collapsed
    case expanded
}
