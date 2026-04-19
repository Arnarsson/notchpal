import AppKit

enum NotchGeometry {

    private static let collapsedPadding: CGFloat = 20

    static func collapsedSize(for screen: NSScreen) -> CGSize {
        if let notch = physicalNotchRect(in: screen) {
            return CGSize(width: notch.width, height: notch.height + collapsedPadding)
        }
        return CGSize(width: 180, height: 32 + collapsedPadding)
    }

    /// List view: sized to fit agents. Active agents get full rows (~46pt),
    /// passive agents pair up in 2-col grid (~40pt per row).
    static func listSize(activeCount: Int, passiveCount: Int) -> CGSize {
        let header: CGFloat = 36 + 24         // notch clearance + header
        let activeH = CGFloat(activeCount) * 44
        let passiveRows = ceil(CGFloat(passiveCount) / 2)
        let passiveH = passiveRows * 36
        let gap: CGFloat = (activeCount > 0 && passiveCount > 0) ? 6 : 0
        let bottom: CGFloat = 24              // bottom bar
        let h = header + activeH + gap + passiveH + bottom
        return CGSize(width: 560, height: max(h, 110))
    }

    /// Per-agent detail sizing — tight to content.
    static func detailSize(for agentId: String) -> CGSize {
        let h: CGFloat = switch agentId {
        case "data":        330
        case "art":         350
        case "animation":   320
        case "coach":       340
        case "story":       370
        case "log":         320
        case "screenshare": 340
        default:            250
        }
        return CGSize(width: 560, height: h)
    }

    static func frame(for state: NotchState, on screen: NSScreen) -> NSRect {
        switch state {
        case .collapsed:
            return centeredTopFrame(size: collapsedSize(for: screen), in: screen)
        case .expanded:
            // Default list size — controller will call resizePanel for specifics
            return centeredTopFrame(size: listSize(activeCount: 3, passiveCount: 4), in: screen)
        }
    }

    static func frame(size: CGSize, on screen: NSScreen) -> NSRect {
        centeredTopFrame(size: size, in: screen)
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
