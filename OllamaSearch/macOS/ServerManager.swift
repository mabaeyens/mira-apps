#if os(macOS)
import Foundation

/// Lightweight connection manager for the macOS thin client.
/// Polls localhost:8000 until the server (run as a launchd LaunchAgent) is ready.
@MainActor
@Observable
final class MacConnectionManager {

    enum State: Equatable {
        case connecting(String)
        case ready
        case failed(String)
    }

    static let shared = MacConnectionManager()

    var state: State = .connecting("Connecting to server…")

    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        state = .connecting("Connecting to server…")
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // 60s timeout: Ollama warm-up can take up to 25s (5 × 5s retries)
            let deadline = Date.now.addingTimeInterval(60)
            while Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                let status = await APIClient.shared.startupStatus()
                switch status {
                case .ready:
                    self?.state = .ready
                    return
                case .starting:
                    self?.state = .connecting("Starting Ollama…")
                case .unavailable:
                    self?.state = .connecting("Connecting to server…")
                }
            }
            self?.state = .failed(
                "Could not reach the Mira server at localhost:8000.\n\n" +
                "Make sure the server is installed and running as a Login Item."
            )
        }
    }

    func retry() {
        start()
    }
}
#endif
