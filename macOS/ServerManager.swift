import Foundation

/// Manages the Python FastAPI server subprocess lifecycle.
///
/// Memory safety:
/// - `process.terminationHandler` uses `[weak self]` to avoid a retain cycle
///   (Process retains its handler closure strongly).
/// - The health-poll Task is stored and cancelled in `deinit`.
@MainActor
@Observable
final class ServerManager {

    enum State: Equatable {
        case idle
        case starting
        case waitingForModel   // server up but model not yet loaded
        case ready
        case failed(String)
    }

    static let shared = ServerManager()

    var state: State = .idle
    var projectPath: String = UserDefaults.standard.string(forKey: "projectPath") ?? ""

    private var process: Process?
    private var pollTask: Task<Void, Never>?

    private init() {}

    deinit {
        pollTask?.cancel()
    }

    // ── Public API ────────────────────────────────────────────────────────────

    func start() {
        guard !projectPath.isEmpty else {
            state = .failed("Project path not configured. Open Settings to set it.")
            return
        }
        guard state != .ready && state != .starting else { return }

        state = .starting
        launchProcess()
        startHealthPoll()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        process?.terminate()
        process = nil
        state = .idle
    }

    // ── Server launch ─────────────────────────────────────────────────────────

    private func launchProcess() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [
            "-c",
            "cd \"\(projectPath)\" && source .venv/bin/activate && python server.py"
        ]
        // Suppress server stdout/stderr from the app's console in release;
        // in debug builds you can remove these lines to see server logs.
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .ready = self.state { return }   // normal quit
                if proc.terminationStatus != 0 {
                    self.state = .failed("Server exited with code \(proc.terminationStatus)")
                }
            }
        }

        do {
            try p.launch()
            process = p
        } catch {
            state = .failed("Could not launch server: \(error.localizedDescription)")
        }
    }

    // ── Health polling ────────────────────────────────────────────────────────

    private func startHealthPoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            let deadline = Date.now.addingTimeInterval(60)   // 60-second timeout
            while Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                let healthy = await APIClient.shared.isHealthy()
                if healthy {
                    await MainActor.run { [weak self] in
                        self?.state = .ready
                    }
                    return
                }

                // After 10s still not up — hint that the model is loading
                if Date.now > deadline.addingTimeInterval(-50) {
                    await MainActor.run { [weak self] in
                        if case .starting = self?.state {
                            self?.state = .waitingForModel
                        }
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.state = .failed("Server did not start within 60 seconds.")
            }
        }
    }
}
