#if os(macOS)
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mab.mira", category: "ServerManager")

/// Lightweight connection manager for the macOS thin client.
/// Polls localhost:8000 until the server (run as a launchd LaunchAgent) is ready.
@MainActor
@Observable
final class MacConnectionManager {

    enum State: Equatable {
        case connecting(String)
        case ready
        /// Server is reachable but this app has no API token, so every request
        /// would 401. Distinct from `.failed` because the fix is entering a
        /// token, not retrying a connection.
        case needsToken
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
            // 60s timeout. Measured 2026-07-26 across four restarts with the model
            // already resident: warm-up took 3.7s to 7.5s. A cold load of a
            // 19GB model has never been measured and is the case this budget
            // exists for, so the 60s stays until it is.
            let deadline = Date.now.addingTimeInterval(60)
            while Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                let status = await APIClient.shared.startupStatus()
                switch status {
                case .ready:
                    self?.state = self?.loadToken() == true ? .ready : .needsToken
                    return
                case .starting:
                    self?.state = .connecting("Starting Mira…")
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

    /// Populate `APIClient.authToken`. Returns false when no token could be
    /// found, so the caller can show the entry UI instead of proceeding into a
    /// wall of 401s.
    ///
    /// The previous version read `~/.local/share/mira/token` directly with
    /// `try?`. Under the App Sandbox that path resolves inside the container and
    /// never exists, and `try?` discarded the miss, so the app ran permanently
    /// unauthenticated while reporting itself connected. See TokenStore.
    @discardableResult
    private func loadToken() -> Bool {
        guard let (token, source) = TokenStore.load() else { return false }
        APIClient.shared.authToken = token
        if case .file(let path) = source {
            logger.info("token read from \(path, privacy: .public) and promoted to the keychain")
        }
        return true
    }

    /// Store a user-supplied token and re-check the connection.
    func submitToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        TokenStore.save(trimmed)
        APIClient.shared.authToken = trimmed
        start()
    }
}
#endif
