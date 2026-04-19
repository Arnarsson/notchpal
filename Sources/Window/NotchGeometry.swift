import AppKit

/// Pure geometry helpers for locating the notch and sizing the expanded panel.
/// No side effects; easy to reason about and (later) unit-test.
enum NotchGeometry {

    /// Collapsed size: matches the physical notch when present, otherwise a synthetic handle.
    /// The notch on 14"/16" M-series MacBooks is ~200pt wide x 32pt tall in points.
    static func collapsedSize(for screen: NSScreen) -> CGSize {
        if let notch = physicalNotchRect(in: screen) {
            return CGSize(width: notch.width, height: notch.height)
        }
        return CGSize(width: 180, height: 32) // synthetic handle for non-notch Macs
    }

    /// Expanded size used during spike. Fixed for now; later read from preferences.
    static let expandedSize = CGSize(width: 520, height: 160)

    /// Returns the frame (in screen coordinates) for the panel in its given state.
    static func frame(for state: NotchState, on screen: NSScreen) -> NSRect {
        switch state {
        case .collapsed:
            let size = collapsedSize(for: screen)
            return centeredTopFrame(size: size, in: screen)
        case .expanded:
            return centeredTopFrame(size: expandedSize, in: screen)
        }
    }

    /// The physical notch rect in screen coordinates, if this screen has one.
    /// Uses `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, which Apple exposes
    /// specifically to let apps account for the notch. The gap between them is the notch.
    static func physicalNotchRect(in screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let notchLeft = left.maxX
        let notchRight = right.minX
        guard notchRight > notchLeft else { return nil }
        let width = notchRight - notchLeft
        // Height: the auxiliary areas sit beside the notch, so their height == notch height.
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
