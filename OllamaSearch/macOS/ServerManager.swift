#if os(macOS)
import Foundation
import Network

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
    /// Advertises _ollamasearch._tcp via the system mDNSResponder so all
    /// network interfaces (WiFi, Ethernet) broadcast the service — the Python
    /// server's zeroconf only binds to loopback and is invisible to iOS.
    private var bonjourService: NetService?

    private init() {}

    // ── Public API ────────────────────────────────────────────────────────────

    func start() {
        guard !projectPath.isEmpty else {
            state = .failed("Project path not configured. Open Settings to set it.")
            return
        }
        guard state != .ready && state != .starting else { return }

        state = .starting

        // Kill any orphaned server.py process from a previous app run.
        // Xcode stop / force-quit does not kill child processes, so without
        // this the old code keeps running and we'd get stale API behaviour.
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", "server.py"]
        try? killer.run()
        killer.waitUntilExit()   // synchronous — completes in <100 ms

        Task {
            // Brief pause so the OS reclaims the port before we bind again
            try? await Task.sleep(for: .milliseconds(300))
            self.launchProcess()
            self.startHealthPoll()
        }
    }

    func stop() {
        bonjourService?.stop()
        bonjourService = nil
        pollTask?.cancel()
        pollTask = nil
        process?.terminate()
        process = nil
        state = .idle
    }

    // ── Server launch ─────────────────────────────────────────────────────────

    private func launchProcess() {
        let p = Process()
        // Resolve the symlink chain (.venv/bin/python → uv-managed python3.12).
        // Process.executableURL does not follow symlinks, so we must resolve first.
        let pythonURL = URL(fileURLWithPath: "\(projectPath)/.venv/bin/python")
            .resolvingSymlinksInPath()
        p.executableURL = pythonURL
        p.arguments = ["server.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        // Discover venv site-packages path (python3.x subfolder may vary)
        let libPath = "\(projectPath)/.venv/lib"
        let sitePackages: String
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: libPath),
           let pyDir = dirs.first(where: { $0.hasPrefix("python") }) {
            sitePackages = "\(libPath)/\(pyDir)/site-packages"
        } else {
            sitePackages = "\(libPath)/python3.12/site-packages"
        }

        p.environment = [
            "PATH": "\(projectPath)/.venv/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "VIRTUAL_ENV": "\(projectPath)/.venv",
            "PYTHONPATH": sitePackages,
            "OLLAMA_HOST": "http://127.0.0.1:11434",
        ]
        // Capture stderr via pipe so we can log it to the Xcode console
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let output = String(data: handle.availableData, encoding: .utf8) ?? ""
            if !output.isEmpty { print("[server] \(output)") }
        }

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
            try p.run()   // Process.run() is the non-deprecated throwing API
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
                        guard let self else { return }
                        self.state = .ready
                        // Register via system mDNSResponder so all interfaces
                        // (WiFi, Ethernet) advertise the service. Python's
                        // zeroconf only binds to loopback and is invisible to iOS.
                        let svc = NetService(
                            domain: "local.",
                            type: "_ollamasearch._tcp",
                            name: "Mira",
                            port: 8000
                        )
                        svc.publish()
                        self.bonjourService = svc
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

#endif
