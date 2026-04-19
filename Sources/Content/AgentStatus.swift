import SwiftUI

/// Stand-in for a future HEKLA agent-status feed.
/// The entire point of this type in the spike is: can we mutate it from LLDB
/// and watch the notch UI update in real time? That validates the content pipeline
/// without needing a real HEKLA connection.
///
/// Usage in LLDB once the app is running:
///   expr AgentStatus.shared.label = "Arkivar indexing 342 files"
///   expr AgentStatus.shared.state = .busy
///
@Observable
final class AgentStatus {
    static let shared = AgentStatus()

    var agent: String = "HEKLA"
    var label: String = "idle"
    var state: State = .idle

    enum State {
        case idle
        case busy
        case attention
        case error

        var color: Color {
            switch self {
            case .idle: .secondary
            case .busy: .green
            case .attention: .yellow
            case .error: .red
            }
        }
    }

    private init() {}
}
