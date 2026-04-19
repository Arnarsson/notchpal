import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controller: NotchController?
    private var statusItem: NSStatusItem?

    var notchController: NotchController? { controller }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory = no Dock icon, no menu bar takeover. Spike is a HUD only.
        NSApp.setActivationPolicy(.accessory)

        // Request accessibility up front. Hover tracking needs it.
        // This is non-blocking: the prompt appears; we proceed regardless.
        promptAccessibility()

        controller = NotchController()
        controller?.show()

        // Connect to Eureka/OpenClaw API
        EurekaBridge.shared.startPolling(interval: 5)

        installQuitOnlyStatusItem()
    }

    // MARK: - Status item

    private func installQuitOnlyStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.roundedtop.fill",
            accessibilityDescription: "NotchPal"
        )
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit NotchPal",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    // MARK: - Permissions

    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        // If the user denies, hover still works when the panel itself is hovered
        // (NSTrackingArea inside the panel is local), but global mouse tracking would require this.
        // For the spike, local tracking is sufficient. We prompt anyway so we're ready for v1.
    }
}
