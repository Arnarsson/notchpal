import SwiftUI

@main
struct NotchPalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No Settings scene in the spike. The app is purely the notch panel.
        // Empty Settings is a workaround to satisfy the App protocol.
        Settings { EmptyView() }
    }
}
