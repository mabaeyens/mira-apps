import Foundation

/// Thin wrapper around all FastAPI endpoints.
/// All methods are `async` and `@MainActor`-safe to call from view models.
@MainActor
final class APIClient {

    static let shared = APIClient()
    private init() {}

    var baseURL: URL = URL(string: "http://127.0.0.1:8000")!

    // ── Health ────────────────────────────────────────────────────────────────

    enum StartupStatus { case ready, starting, unavailable }

    /// Returns the server's startup state: ready (200), starting (503), or unreachable.
    func startupStatus() async -> StartupStatus {
        guard let healthURL = URL(string: "/health", relativeTo: baseURL) else { return .unavailable }
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return .ready
            case 503: return .starting
            default:  return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    /// Returns true when the server at `baseURL` is up and ready.
    func isHealthy() async -> Bool {
        await startupStatus() == .ready
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

    // ── Chat ──────────────────────────────────────────────────────────────────

    /// Build the URLRequest for POST /chat (multipart).
    /// The caller passes it to `SSEClient.shared.stream(request:)`.
    func chatRequest(
        message: String,
        conversationId: String,
        attachments: [AttachmentPayload] = []
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            message: message,
            conversationId: conversationId,
            attachments: attachments,
            boundary: boundary
        )
        return request
    }

    func cancel() async {
        guard let url = URL(string: "/cancel", relativeTo: baseURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
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

    // ── Conversations ─────────────────────────────────────────────────────────

    func listConversations() async throws -> [Conversation] {
        let url = baseURL.appendingPathComponent("conversations")
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(ConversationList.self, from: data)
        return obj.conversations
    }

    func createConversation() async throws -> String {
        guard let url = URL(string: "/conversations", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(NewConversationResponse.self, from: data)
        return obj.id
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
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONDecoder().decode(MessageList.self, from: data)
        return obj.messages
    }

    // ── Multipart builder ─────────────────────────────────────────────────────

    private func multipartBody(
        message: String,
        conversationId: String,
        attachments: [AttachmentPayload],
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

        for attachment in attachments {
            switch attachment {
            case .fileData(let name, let data, let mimeType):
                append("--\(boundary)\(crlf)")
                append("Content-Disposition: form-data; name=\"files\"; filename=\"\(name)\"\(crlf)")
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
    var errorDescription: String? { "Invalid server URL" }
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

private struct ConversationList: Decodable {
    let conversations: [Conversation]
}

private struct MessageList: Decodable {
    let messages: [ConversationMessage]
}
