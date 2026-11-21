import Foundation

/// The demo "server": answers every request for `DemoMode.host` from memory,
/// and fails every other http(s) request locally while demo is on.
///
/// Registered for `URLSession.shared` by `DemoMode.register()` and listed in the
/// SSE session's `protocolClasses`. Those are the only two sessions the app has.
///
/// A request for the demo host is always claimed, in demo or not, so the name
/// is never handed to the resolver: outside demo it simply fails.
nonisolated final class DemoURLProtocol: URLProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var stopped = false

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // ── URLProtocol ───────────────────────────────────────────────────────────

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        if url.host == DemoMode.host { return true }
        return DemoMode.isActive
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == DemoMode.host, DemoMode.isActive else {
            if request.url?.host != DemoMode.host { DemoMode.noteBlocked() }
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        DemoMode.noteServed()
        route(method: (request.httpMethod ?? "GET").uppercased(),
              path: url.path.split(separator: "/").map(String.init))
    }

    override func stopLoading() {
        lock.lock(); stopped = true; lock.unlock()
    }

    // ── Routes ────────────────────────────────────────────────────────────────

    private func route(method: String, path: [String]) {
        let store = DemoStore.shared
        switch (method, path.first ?? "", path.count) {

        case ("GET", "health", 1):
            // No `engine_state`: the idle-unload lifecycle reads as off.
            json(["status": "ok", "backend_ready": true])

        case ("GET", "info", 1):
            json(["model": DemoContent.modelName, "backend": DemoContent.backend, "host": "demo",
                  "context_window": DemoContent.contextWindow, "hardware": "Demo, no server"])

        case ("GET", "backend", 1):
            json(["backend": DemoContent.backend, "model": DemoContent.modelName, "host": "demo",
                  "context_window": DemoContent.contextWindow])

        case ("GET", "backends", 1):
            json([["id": "demo", "label": DemoContent.modelName, "backend": DemoContent.backend,
                   "model": DemoContent.modelName, "context_window": DemoContent.contextWindow,
                   "active": true, "available": true, "detail": ""]])

        case ("GET", "models", 1):
            json(["backends": [], "mlx_lm": [], "ollama": [],
                  "active": ["backend": DemoContent.backend, "model_id": DemoContent.modelName]])

        case ("GET", "hardware", 1):
            json(["system_memory": ["advisory": "ok"]])

        case ("GET", "projects", 1):
            json(["projects": []])

        case ("GET", "conversations", 1):
            json(["conversations": store.conversationList()])

        case ("POST", "conversations", 1):
            json(["id": store.create(), "title": "New conversation"])

        case ("GET", "conversations", 3) where path[2] == "messages":
            if let messages = store.messages(for: path[1]) {
                json(["messages": messages])
            } else {
                json(["detail": "Conversation not found"], status: 404)
            }

        case ("PATCH", "conversations", 2):
            // A rename. Moving to a project (`project_id`) has nothing to move to.
            if let title = bodyJSON()["title"] as? String { store.rename(path[1], title: title) }
            json(["ok": true])

        case ("DELETE", "conversations", 2):
            store.delete(path[1])
            json(["ok": true])

        case ("GET", "memories", 1):
            json(["memories": store.memoryList()])

        case ("POST", "memories", 1):
            json(store.addMemory(bodyJSON()["text"] as? String ?? ""))

        case ("DELETE", "memories", 2):
            if let id = Int(path[1]) { store.deleteMemory(id) }
            json(["ok": true])

        case ("POST", "chat", 1):
            chat()

        case ("POST", "cancel", 1):
            json(["ok": true])

        case ("POST", "reset", 1):
            json(["conv_id": store.create(), "title": "New conversation"])

        case ("POST", "compact", 1):
            json(["message": "Nothing to compact in the demo."])

        case ("POST", "models", 2) where path[1] == "pull":
            sse([(0, ["type": "error", "message": DemoContent.unavailable])])

        default:
            // Switching models or backends, projects, the engine lifecycle:
            // nothing to do without a server. 409 is what `unloadEngine` and the
            // rest already treat as "not now", and the detail says why.
            json(["detail": DemoContent.unavailable], status: 409)
        }
    }

    // ── Chat ──────────────────────────────────────────────────────────────────

    /// A canned reply as the same event stream mira-core sends: thinking, then
    /// tokens, then `stats`, `done` and `title`. The turn is added to the
    /// in-memory conversation once it has finished, as the server does, so a
    /// stopped turn leaves nothing behind.
    private func chat() {
        let body = bodyData()
        let message = Self.formField("message", in: body) ?? ""
        var convId = Self.formField("conversation_id", in: body) ?? ""
        let store = DemoStore.shared

        var title: String? = nil
        if convId.isEmpty || !store.exists(convId) {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Demo conversation" : String(trimmed.prefix(40))
            convId = store.create(title: name)
            title = name
        } else if store.messages(for: convId)?.isEmpty == true {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                title = String(trimmed.prefix(40))
                store.rename(convId, title: title ?? "")
            }
        }

        let reply = DemoContent.reply + Self.diagnostics()
        let thinking = DemoContent.replyThinking

        var events: [(TimeInterval, [String: Any])] = []
        for piece in Self.pieces(of: thinking, wordsPerPiece: 4) {
            events.append((0.12, ["type": "thinking", "content": piece]))
        }
        for piece in Self.pieces(of: reply, wordsPerPiece: 1) {
            events.append((0.035, ["type": "token", "content": piece]))
        }
        let outputTokens = reply.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        events.append((0.05, ["type": "stats", "input_tokens": 48, "output_tokens": outputTokens, "context_pct": 0.4]))
        events.append((0, ["type": "done", "content": reply]))
        if let title {
            events.append((0, ["type": "title", "conv_id": convId, "title": title]))
        }

        let id = convId
        sse(events) {
            store.append([.init(role: "user", content: message),
                          .init(role: "assistant", content: reply, thinking: thinking)], to: id)
        }
    }

    /// `-MiraDemoDiagnostics 1` on the launch line: the UI test reads the request
    /// counters out of the reply. Debug builds only; empty otherwise.
    private static func diagnostics() -> String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "MiraDemoDiagnostics") {
            let c = DemoMode.counters
            return "\n\n[demo diagnostics: served=\(c.served) blocked=\(c.blocked)]"
        }
        #endif
        return ""
    }

    /// The text cut into runs of words, each keeping its trailing whitespace,
    /// so the pieces concatenate back to the text exactly.
    static func pieces(of text: String, wordsPerPiece: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        var words = 0
        var inWord = false
        for ch in text {
            let space = ch == " " || ch == "\n"
            if !space, !inWord, words == wordsPerPiece {
                pieces.append(current)
                current = ""
                words = 0
            }
            if !space, !inWord { words += 1 }
            inWord = !space
            current.append(ch)
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // ── Responses ─────────────────────────────────────────────────────────────

    private func json(_ object: Any, status: Int = 200) {
        guard let url = request.url,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Sends each event after its delay, off the caller's thread, and stops at
    /// once when the request is cancelled. `completed` runs only if every event
    /// went out.
    private func sse(_ events: [(TimeInterval, [String: Any])], completed: @escaping @Sendable () -> Void = {}) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/event-stream",
                                                            "Cache-Control": "no-cache"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let lines: [(TimeInterval, Data)] = events.compactMap { delay, event in
            guard let data = try? JSONSerialization.data(withJSONObject: event),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return (delay, Data("data: \(text)\n\n".utf8))
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for (delay, line) in lines {
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                if isStopped { return }
                client?.urlProtocol(self, didLoad: line)
            }
            if isStopped { return }
            completed()
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    // ── Request body ──────────────────────────────────────────────────────────

    /// By the time a request reaches a URLProtocol its body has usually been
    /// moved from `httpBody` to `httpBodyStream`.
    private func bodyData() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func bodyJSON() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: bodyData())) as? [String: Any] ?? [:]
    }

    /// One text field out of a multipart body, found by bytes so that binary
    /// attachments in the same body cannot break the decoding.
    static func formField(_ name: String, in body: Data) -> String? {
        guard let start = body.range(of: Data("name=\"\(name)\"\r\n\r\n".utf8)),
              let end = body.range(of: Data("\r\n--".utf8), in: start.upperBound..<body.endIndex) else { return nil }
        return String(data: body.subdata(in: start.upperBound..<end.lowerBound), encoding: .utf8)
    }
}
