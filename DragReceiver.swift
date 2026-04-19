import SwiftUI
import UniformTypeIdentifiers

/// Wraps SwiftUI's `onDrop` to hand back `URL`s and handle the async provider dance.
/// Accepts any file item; validation (type filtering, size limits) lives in the caller.
struct DragReceiver: ViewModifier {
    let onDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    onDrop(url)
                }
            }
            return true
        }
    }
}

extension View {
    func receiveDroppedFile(_ onDrop: @escaping (URL) -> Void) -> some View {
        modifier(DragReceiver(onDrop: onDrop))
    }
}
