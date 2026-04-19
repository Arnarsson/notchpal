import SwiftUI

/// SwiftUI-native hover tracking with enter/exit debounce.
/// Using `onHover` inside the SwiftUI tree is simpler and more reliable than
/// NSTrackingArea for this spike — the hit-testing handles itself and we don't
/// need global mouse position, only "is the cursor over our view right now."
///
/// Debounce prevents flicker when the cursor skims the edge of the notch.
struct HoverTracker: ViewModifier {
    let enterDelay: Duration
    let exitDelay: Duration
    let onChange: (Bool) -> Void

    @State private var pendingTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            pendingTask?.cancel()
            pendingTask = Task { @MainActor in
                let delay = isHovering ? enterDelay : exitDelay
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                onChange(isHovering)
            }
        }
    }
}

extension View {
    /// Call `onChange` when hover state has been stable for the given delays.
    func trackHover(
        enter: Duration = .milliseconds(80),
        exit: Duration = .milliseconds(300),
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(HoverTracker(enterDelay: enter, exitDelay: exit, onChange: onChange))
    }
}
