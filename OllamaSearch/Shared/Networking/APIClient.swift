import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mab.mira", category: "APIClient")

/// Thin wrapper around all FastAPI endpoints.
/// All methods are `async` and `@MainActor`-safe to call from view models.
@MainActor
final class APIClient {

    static let shared = APIClient()
    private init() {}

    // Compile-time constant literal — URL(string:) only returns nil for malformed strings.
    var baseURL: URL = URL(string: "http://127.0.0.1:8000")!

    // ── Health ────────────────────────────────────────────────────────────────

    enum StartupStatus { case ready, starting, unavailable }

    struct HealthResponse {
        let startupStatus: StartupStatus
        /// True when Mira is up AND the inference backend (oMLX/Ollama) is reachable with its model.
        let backendReady: Bool
    }

    /// Returns full health info — startup state + whether the inference backend is ready.
    func health() async -> HealthResponse {
        guard let healthURL = URL(string: "/health", relativeTo: baseURL) else {
            return HealthResponse(startupStatus: .unavailable, backendReady: false)
        }
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 5.0
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode
            switch code {
            case 200:
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let backendReady = json?["backend_ready"] as? Bool ?? true
                return HealthResponse(startupStatus: .ready, backendReady: backendReady)
            case 503:
                return HealthResponse(startupStatus: .starting, backendReady: false)
            default:
                return HealthResponse(startupStatus: .unavailable, backendReady: false)
            }
        } catch {
            return HealthResponse(startupStatus: .unavailable, backendReady: false)
        }
    }

    /// Returns the server's startup state: ready (200), starting (503), or unreachable.
    func startupStatus() async -> StartupStatus {
        await health().startupStatus
    }

    /// Returns true when the server at `baseURL` is up and ready.
    func isHealthy() async -> Bool {
        await startupStatus() == .ready
    }

    /// Trigger the server to start the inference backend (POST /backend with current backend).
    /// Uses a 120 s timeout — inference servers can take a while to start.
    func startCurrentBackend() async throws -> BackendInfo {
        try await switchBackend(to: await getBackend().backend)
    }

    /// Returns true when the server at the given URL responds within `timeout` seconds.
    func isHealthy(at url: URL, timeout: TimeInterval = 1.5) async -> Bool {
        guard let healthURL = URL(string: "/health", relativeTo: url) else { return false }
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = timeout
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Races a `/health` check against a hard `deadline` in seconds.
    ///
    /// `nonisolated` is intentional: it forces the task group and its children
    /// off the main actor onto the cooperative thread pool, making `Task.sleep`
    /// a guaranteed hard deadline even when a VPN (e.g. Tailscale) is active.
    /// A `@MainActor` task group has its children scheduled on the main actor,
    /// where VPN-induced network stalls can prevent sleep continuations from firing.
    nonisolated func probe(_ url: URL, deadline: Double = 5) async -> Bool {
        guard let healthURL = URL(string: "/health", relativeTo: url) else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var req = URLRequest(url: healthURL)
                req.timeoutInterval = deadline
                do {
                    let (_, response) = try await URLSession.shared.data(for: req)
                    return (response as? HTTPURLResponse)?.statusCode == 200
                } catch { return false }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(deadline))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // ── Backend switching ─────────────────────────────────────────────────────

    func getBackend() async throws -> BackendInfo {
        let url = baseURL.appendingPathComponent("backend")
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(BackendInfo.self, from: data)
    }

    /// POST /backend — blocks until the server has stopped the old backend and
    /// started the new one (up to 120 s). Returns the updated BackendInfo.
    func switchBackend(to backend: String) async throws -> BackendInfo {
        let url = baseURL.appendingPathComponent("backend")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["backend": backend])
        req.timeoutInterval = 120
        _ = try await URLSession.shared.data(for: req)
        return try await getBackend()
    }

    // ── Server info ───────────────────────────────────────────────────────────

    func fetchServerInfo() async throws -> ServerInfo {
        let url = baseURL.appendingPathComponent("info")
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }

    // ── Chat ──────────────────────────────────────────────────────────────────

    /// Build the URLRequest for POST /chat (multipart).
    /// The caller passes it to `SSEClient.shared.stream(request:)`.
    func chatRequest(
        message: String,
        conversationId: String,
        attachments: [AttachmentPayload] = [],
        thinkingEnabled: Bool = false
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        // 64-hex-char boundary makes accidental collision with file content statistically impossible.
        let boundary = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            message: message,
            conversationId: conversationId,
            attachments: attachments,
            thinkingEnabled: thinkingEnabled,
            boundary: boundary
        )
        return request
    }

    func cancel() async {
        guard let url = URL(string: "/cancel", relativeTo: baseURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        do {
            _ = try await URLSession.shared.data(for: req)
        } catch {
            // Non-fatal: local streaming state is already stopped.
            logger.debug("Cancel request failed: \(error)")
        }
    }

    func reset() async throws -> (convId: String, title: String) {
        guard let url = URL(string: "/reset", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(ResetResponse.self, from: data)
        return (obj.convId, obj.title)
    }

    /// Returns the banner message from the server ("Nothing to compact yet." or the summary notice).
    func compact() async throws -> String {
        guard let url = URL(string: "/compact", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(CompactResponse.self, from: data)
        return obj.message
    }

    // ── Conversations ─────────────────────────────────────────────────────────

    func listConversations() async throws -> [Conversation] {
        let url = baseURL.appendingPathComponent("conversations")
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(ConversationList.self, from: data)
        return obj.conversations
    }

    func createConversation(projectId: String? = nil) async throws -> String {
        guard let url = URL(string: "/conversations", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let pid = projectId {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["project_id": pid])
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(NewConversationResponse.self, from: data)
        return obj.id
    }

    // ── Projects ──────────────────────────────────────────────────────────────

    func listProjects() async throws -> [Project] {
        let url = baseURL.appendingPathComponent("projects")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ProjectList.self, from: data).projects
    }

    func createProject(name: String, localPath: String?, githubRepo: String?) async throws -> Project {
        guard let url = URL(string: "/projects", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["name": name]
        if let lp = localPath { body["local_path"] = lp }
        if let gh = githubRepo { body["github_repo"] = gh }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.detail ?? "Server error \(http.statusCode)"
            throw APIError.serverError(msg)
        }
        return try JSONDecoder().decode(Project.self, from: data)
    }

    func deleteProject(id: String) async throws {
        guard let url = URL(string: "/projects/\(id)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }

    func renameConversation(id: String, title: String) async throws {
        guard let url = URL(string: "/conversations/\(id)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["title": title])
        _ = try await URLSession.shared.data(for: req)
    }

    func deleteConversation(id: String) async throws {
        guard let url = URL(string: "/conversations/\(id)", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }

    func getMessages(conversationId: String) async throws -> [ConversationMessage] {
        let url = baseURL.appendingPathComponent("conversations/\(conversationId)/messages")
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(MessageList.self, from: data)
        return obj.messages
    }

    // ── Multipart builder ─────────────────────────────────────────────────────

    private func multipartBody(
        message: String,
        conversationId: String,
        attachments: [AttachmentPayload],
        thinkingEnabled: Bool = false,
        boundary: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        func field(_ name: String, _ value: String) {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            append(value)
            append(crlf)
        }

        field("message", message)
        field("conversation_id", conversationId)
        field("thinking_enabled", thinkingEnabled ? "true" : "false")

        for attachment in attachments {
            switch attachment {
            case .fileData(let name, let data, let mimeType):
                let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                append("--\(boundary)\(crlf)")
                append("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeName)\"\(crlf)")
                append("Content-Type: \(mimeType)\(crlf)\(crlf)")
                body.append(data)
                append(crlf)
            case .filePath(let path):
                field("paths", path)
            }
        }

        append("--\(boundary)--\(crlf)")
        return body
    }
}

// ── Supporting types ──────────────────────────────────────────────────────────

enum AttachmentPayload {
    case fileData(name: String, data: Data, mimeType: String)
    case filePath(String)
}

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid server URL"
        case .serverError(let m): return m
        }
    }
}

private struct NewConversationResponse: Decodable {
    let id: String
    let title: String
}

private struct ResetResponse: Decodable {
    let convId: String
    let title: String
    enum CodingKeys: String, CodingKey {
        case convId = "conv_id"
        case title
    }
}

private struct CompactResponse: Decodable {
    let message: String
}

private struct ConversationList: Decodable {
    let conversations: [Conversation]
}

private struct ProjectList: Decodable {
    let projects: [Project]
}

private struct MessageList: Decodable {
    let messages: [ConversationMessage]
}

private struct APIErrorResponse: Decodable {
    let detail: String
}
