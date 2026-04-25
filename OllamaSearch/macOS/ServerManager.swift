#if os(macOS)
import Foundation

/// Lightweight connection manager for the macOS thin client.
/// Polls localhost:8000 until the server (run as a launchd LaunchAgent) is ready.
@MainActor
@Observable
final class MacConnectionManager {

    enum State: Equatable {
        case connecting
        case ready
        case failed(String)
    }

    static let shared = MacConnectionManager()

    var state: State = .connecting

    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        state = .connecting
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            let deadline = Date.now.addingTimeInterval(30)
            while Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                let healthy = await APIClient.shared.isHealthy()
                if healthy {
                    self?.state = .ready
                    return
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
