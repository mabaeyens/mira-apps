import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mab.mira", category: "ChatViewModel")

/// Drives the main chat view. All mutations happen on @MainActor (the main thread).
///
/// Memory safety:
/// - `streamTask` is cancelled in deinit and before each new send.
/// - Token throttle uses `[weak self]` in its Timer closure to prevent
///   a Timer → closure → self → Timer retain cycle.
@MainActor
@Observable
final class ChatViewModel {

    // ── State ────────────────────────────────────────────────────────────────

    var messages: [Message] = []
    var conversations: [Conversation] = []
    var projects: [Project] = []
    var currentConvId: String = ""

    var activeProject: Project? {
        guard !currentConvId.isEmpty,
              let conv = conversations.first(where: { $0.id == currentConvId }),
              let pid = conv.projectId
        else { return nil }
        return projects.first(where: { $0.id == pid })
    }
    var isStreaming: Bool = false
    var inputText: String = ""
    var thinkingEnabled: Bool = false
    var thinkingContent: String? = nil
    var isThinkingActive: Bool = false
    var currentBackend: String = "ollama"
    var modelName: String = ""
    var contextWindow: Int = 0
    var isSwitchingBackend: Bool = false
    var showModelPicker: Bool = false
    var switchStatusMessage: String = ""
    var backendReady: Bool = true      // optimistic; polling corrects it
    var backendLoadingSince: Date? = nil  // set when backend_ready is first false after connect
    var isStartingBackend: Bool = false
    var pendingAttachments: [AttachmentPayload] = []
    var stagedAttachmentNames: [String] = []

    // Status line
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var contextPct: Double = 0

    // In-progress search/fetch/tool indicators (cleared when done)
    var currentSearchQuery: String? = nil
    var isFetching: Bool = false
    var currentToolLabel: String? = nil

    var errorMessage: String? = nil
    /// Non-nil while a conversation's message history is being fetched.
    /// The value is the ID being loaded, used to show a per-row spinner.
    var loadingConvId: String? = nil
    /// True while the conversation list is being fetched from the server.
    var isLoadingConversations: Bool = false

    // ── Internals ────────────────────────────────────────────────────────────

    private var streamTask: Task<Void, Never>?
    // Tracks an in-flight POST /cancel so send() can await it before starting
    // a new request, preventing a race where the new inference starts before
    // the server-side cancel lands (which produced double responses).
    private var cancelTask: Task<Void, Never>?
    // Stale-connection watchdog: fires if no SSE event (including heartbeat)
    // arrives for >15 s during active streaming.
    private var staleConnectionTask: Task<Void, Never>?
    private var lastEventDate = Date.distantPast

    // ── Slow-connection patience messages ─────────────────────────────────────
    // Shown after 3 s of streaming with no tokens yet. Rotates every 6 s.
    var streamingWaitMessage: String? = nil
    private var waitMessageTask: Task<Void, Never>?

    private static let waitingMessages: [String] = [
        "Local models take their time — hang tight",
        "Good things come to those who wait…",
        "Thinking hard about this one",
        "The model is working on it…",
        "Generating your response…",
        "Almost there — local inference can be slow",
        "Please be patient, this might take a moment",
        "Crunching the tokens…",
        "Your local AI is busy thinking",
        "Processing… grab a coffee ☕",
        "This is the price of privacy — worth it",
        "100% local, 100% private, occasionally slow",
        "No cloud, no rush — just your machine",
        "Running entirely on your hardware",
        "Patience, the model is doing its best",
        "Still here, still thinking…",
        "Large responses take a little longer",
        "Working through your request…",
        "Your data never left this machine",
        "On-device AI — give it a moment",
        "Thinking at the speed of silicon…",
        "Warming up the weights…",
        "One token at a time…",
        "The wheels are turning",
        "Complex questions deserve careful answers",
        "Inference in progress — please wait",
        "Not a cloud service — be patient",
        "Locally run, locally slow at times",
        "Your question is being processed",
        "Hang tight while I think this through",
        "Taking a moment to get this right",
        "Almost ready — just a few more seconds",
        "Patience is a virtue, especially with LLMs",
        "The model is giving this its full attention",
        "Your hardware is working overtime",
        "Composing a thoughtful response…",
        "Generating — this depends on your hardware",
        "Local model, local pace",
        "Slower than the cloud, more private than it too",
        "Your GPU/CPU is hard at work",
        "Still generating — complex tasks take longer",
        "A response is being crafted for you",
        "Thinking… don't go anywhere",
        "Inference underway",
        "This one might take a bit longer",
        "On-device reasoning in progress",
        "Your assistant is thinking carefully",
        "The model hasn't given up — it's still going",
        "Sometimes slow is just… thorough",
        "Processing with full context…",
        "No timeout here — take as long as you need",
        "Running the full model, not a trimmed one",
        "Locally hosted means no rate limits",
        "Still generating — feel free to wait",
        "The longer the wait, the more thorough the answer",
        "Heating up the inference engine…",
        "Your machine is doing the heavy lifting",
        "Mira is thinking…",
        "Generating tokens, one by one",
        "This is local AI — patience rewarded",
        "A good answer is worth waiting for",
        "The model is fully engaged with your request",
        "Working at full capacity…",
        "Local inference: no throttling, no rush",
        "Thinking at inference speed…",
        "On your hardware, on your terms",
        "Computation in progress…",
        "Still crafting your response",
        "Your context window is being processed",
        "Don't worry — it hasn't crashed",
        "Just a moment more…",
        "The bigger the model, the longer the wait",
        "Quality over speed",
        "Hang in there — response incoming",
        "Slower than ChatGPT, more private though",
        "Your patience is appreciated",
        "Running inference locally…",
        "Almost done thinking…",
        "Local AI is worth the wait",
        "Still at it — complex queries take time",
        "Your assistant is fully focused on this",
        "Response generation in progress",
        "Taking a deep breath and thinking…",
        "Still working — check back in a moment",
        "Inference can't be rushed — almost there",
        "The model is doing its thing",
        "Generating carefully…",
        "No shortcuts — full generation in progress",
        "A thoughtful response takes time",
        "Running on local hardware — patience pays off",
        "Busy generating your answer",
        "Your request is in good hands",
        "The model is still thinking",
        "Processing at local inference speed",
        "Generating — network not involved",
        "Still here, still working",
        "Taking longer than usual — still going",
        "The response is on its way",
        "Patience mode activated",
        "Your local assistant is deep in thought",
        "Still thinking — this is a good sign",
    ]

    // Token throttle: accumulate tokens, flush every 100ms to avoid
    // re-rendering swift-markdown-ui on every individual token.
    // Uses a Task instead of Timer — Task closures inherit @MainActor context,
    // avoiding the nonisolated-closure issue that Timer callbacks have.
    private var pendingTokenBuffer: String = ""
    private var flushTask: Task<Void, Never>?

    // Non-empty only when sending the first message of a conversation, so
    // finishStreaming() can fall back to the user's prompt as the title if the
    // server never emitted a .title event (e.g. the stream timed out).
    private var pendingFirstMessage: String = ""
    private var receivedTitleDuringStream: Bool = false

    private let api = APIClient.shared
    private let sse = SSEClient.shared
    // No deinit needed: streamTask/flushTask use [weak self] so self can be
    // deallocated freely; stopStreaming() handles explicit cancellation.

    // ── Public API ────────────────────────────────────────────────────────────

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isStreaming else { return }

        if text.hasPrefix("/rename ") {
            let newTitle = String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            inputText = ""
            if !newTitle.isEmpty, !currentConvId.isEmpty {
                renameConversation(currentConvId, title: newTitle)
            }
            return
        }

        if text.lowercased() == "/compact" {
            inputText = ""
            Task {
                do {
                    let msg = try await api.compact()
                    messages.append(.info(msg))
                } catch {
                    errorMessage = "Compact failed: \(error.localizedDescription)"
                }
            }
            return
        }

        inputText = ""
        let attachments = pendingAttachments
        pendingAttachments = []
        stagedAttachmentNames = []

        // Capture image data for inline thumbnails before clearing attachments
        let imageData = attachments.compactMap { att -> Data? in
            if case .fileData(_, let data, let mime) = att, mime.hasPrefix("image/") { return data }
            return nil
        }

        // Track before appending: if no user messages exist yet, this is the first.
        // finishStreaming() uses this to auto-title the conversation when the server's
        // .title event never arrives (e.g. stream timed out).
        let isFirstMessage = !messages.contains(where: { $0.role == .user })
        pendingFirstMessage = isFirstMessage ? text : ""
        receivedTitleDuringStream = false

        // Add user bubble immediately
        messages.append(Message(role: .user, content: text, imageAttachments: imageData))

        // Add an empty streaming assistant bubble
        let assistantMsg = Message(role: .assistant)
        messages.append(assistantMsg)

        isStreaming = true
        currentSearchQuery = nil
        isFetching = false
        currentToolLabel = nil
        thinkingContent = nil
        isThinkingActive = false

        // Show "Sending…" immediately so the user sees feedback within 100 ms.
        // After 5 s with no tokens, rotate through patience messages until the
        // first token arrives (or streaming stops).
        streamingWaitMessage = "Sending…"
        waitMessageTask?.cancel()
        waitMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(5_000))
            guard let self, !Task.isCancelled else { return }
            while !Task.isCancelled {
                self.streamingWaitMessage = Self.waitingMessages.randomElement()
                try? await Task.sleep(for: .milliseconds(6_000))
            }
        }

        // Reset heartbeat clock then start watchdog: if no event arrives for >15 s
        // (including heartbeats, which come every 5 s), treat as dropped connection.
        lastEventDate = Date()
        staleConnectionTask?.cancel()
        staleConnectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.isStreaming else { break }
                if Date().timeIntervalSince(self.lastEventDate) > 15 {
                    self.errorMessage = "Connection lost — the server may be sleeping. Tap Resend when it's back."
                    self.stopStreaming()
                    break
                }
            }
        }

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            // Await any pending server-side cancel from stopStreaming() so we
            // don't race the new chat request against an outstanding cancel POST.
            _ = await self.cancelTask?.value
            self.cancelTask = nil
            guard !Task.isCancelled else { return }
            let request = self.api.chatRequest(
                message: text,
                conversationId: self.currentConvId,
                attachments: attachments,
                thinkingEnabled: self.thinkingEnabled
            )
            do {
                for try await event in self.sse.stream(request: request) {
                    guard !Task.isCancelled else { break }
                    self.handle(event: event, assistantMsgId: assistantMsg.id)
                }
            } catch is CancellationError {
                // App backgrounded or user tapped Stop — not an error.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URLSession cancelled (app lifecycle) — not an error.
            } catch {
                self.errorMessage = Self.isNetworkError(error)
                    ? "Connection lost — the server may be sleeping. Tap Resend when it's back."
                    : error.localizedDescription
            }
            self.finishStreaming(msgId: assistantMsg.id)
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        waitMessageTask?.cancel()
        waitMessageTask = nil
        staleConnectionTask?.cancel()
        staleConnectionTask = nil
        streamingWaitMessage = nil
        isThinkingActive = false
        currentToolLabel = nil
        // Store (don't fire-and-forget) so send() can await this before the next request.
        cancelTask = Task { [weak self] in
            guard let self else { return }
            await self.api.cancel()
        }
        flushPendingTokens()
        if let idx = messages.indices.last, messages[idx].role == .assistant {
            messages[idx].isStreaming = false
        }
        isStreaming = false
    }

    /// Non-nil when the last exchange failed (empty assistant response, not streaming).
    /// Used to show the Resend / Edit buttons on the last user bubble.
    var lastFailedUserMessage: Message? {
        guard !isStreaming,
              let last = messages.last, last.role == .assistant, last.content.isEmpty,
              messages.count >= 2,
              messages[messages.count - 2].role == .user
        else { return nil }
        return messages[messages.count - 2]
    }

    /// Drops the failed exchange and re-sends the same question.
    func resendLast() {
        guard let userMsg = lastFailedUserMessage else { return }
        let text = userMsg.content
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
        send()
    }

    /// Drops the failed exchange and restores the question to the input field.
    func editLast() {
        guard let userMsg = lastFailedUserMessage else { return }
        let text = userMsg.content
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
    }

    func newConversation(projectId: String? = nil) {
        streamTask?.cancel()
        thinkingEnabled = false
        Task {
            do {
                let convId = try await api.createConversation(projectId: projectId)
                currentConvId = convId
                messages = []
                inputTokens = 0; outputTokens = 0; contextPct = 0
                await loadConversations()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadBackend() async {
        do {
            let info = try await APIClient.shared.getBackend()
            currentBackend = info.backend
            modelName = info.model
            contextWindow = info.contextWindow
        } catch {
            // Non-fatal — UI defaults to "ollama"
        }
    }

    /// Check Mira health and update backendReady. Call once on connect, then poll.
    func refreshBackendHealth() async {
        let h = await APIClient.shared.health()
        if h.startupStatus == .ready {
            if h.backendReady {
                backendLoadingSince = nil
            } else if backendLoadingSince == nil {
                backendLoadingSince = Date()
            }
            backendReady = h.backendReady
        }
        // If Mira itself isn't up yet, leave backendReady unchanged.
    }

    /// Start periodic backend health polling every 10 s (cancels on next call).
    private var healthPollTask: Task<Void, Never>?

    func startHealthPolling() {
        healthPollTask?.cancel()
        healthPollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Poll faster during startup so the loading banner clears promptly.
                let isReady = await self?.backendReady ?? true
                let interval: Duration = isReady ? .seconds(10) : .seconds(3)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                await self?.refreshBackendHealth()
            }
        }
    }

    /// Tell the server to start its configured inference backend.
    func startBackend() async {
        guard !isStartingBackend, !isSwitchingBackend else { return }
        isStartingBackend = true
        switchStatusMessage = "Starting \(modelName.isEmpty ? currentBackend : modelName)…"
        do {
            let info = try await APIClient.shared.startCurrentBackend()
            currentBackend = info.backend
            modelName = info.model
            contextWindow = info.contextWindow
            backendReady = true
        } catch {
            errorMessage = "Could not start backend: \(error.localizedDescription)"
        }
        switchStatusMessage = ""
        isStartingBackend = false
    }

    func switchBackend(to backend: String) async {
        guard !isSwitchingBackend else { return }
        isSwitchingBackend = true

        let fromName = modelName.isEmpty ? currentBackend : modelName
        let toBackendLabel = backend == "omlx" ? "oMLX" : "Ollama"
        switchStatusMessage = "Stopping \(fromName)…"

        let statusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Starting \(toBackendLabel)…"
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Loading model weights…"
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Almost ready…"
        }

        do {
            let info = try await APIClient.shared.switchBackend(to: backend)
            statusTask.cancel()
            currentBackend = info.backend
            modelName = info.model
            contextWindow = info.contextWindow
            showModelPicker = false
            let backendLabel = info.backend == "omlx" ? "oMLX" : "Ollama"
            messages.append(.info("— Switched to \(info.model) (\(backendLabel)). Conversation history is preserved. —"))
        } catch {
            statusTask.cancel()
            errorMessage = "Failed to switch model: \(error.localizedDescription)"
        }
        switchStatusMessage = ""
        isSwitchingBackend = false
    }

    func loadProjects() async {
        do {
            projects = try await api.listProjects()
        } catch {
            // Non-fatal — sidebar will just show empty projects section
        }
    }

    func addProject(name: String, localPath: String?, githubRepo: String?) async throws {
        let project = try await api.createProject(name: name, localPath: localPath, githubRepo: githubRepo)
        projects.append(project)
    }

    func deleteProject(_ id: String) {
        Task {
            do {
                try await api.deleteProject(id: id)
                projects.removeAll { $0.id == id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectConversation(_ id: String) {
        guard (id != currentConvId || messages.isEmpty), loadingConvId != id else { return }
        streamTask?.cancel()
        loadingConvId = id
        Task {
            defer { loadingConvId = nil }
            // Task-based timeout: URLRequest.timeoutInterval is unreliable when
            // VPN routing silently drops packets (no TCP RST). Cancelling the
            // inner Task guarantees work.value throws within the limit regardless.
            // Large histories over Tailscale/5G can be slow — allow 60 s.
            let work = Task { try await api.getMessages(conversationId: id) }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(60))
                work.cancel()
            }
            defer { timeout.cancel() }
            do {
                let history = try await work.value
                currentConvId = id
                messages = history.map { m in
                    let role: Message.Role
                    switch m.role {
                    case "user":      role = .user
                    case "assistant": role = .assistant
                    default:          role = .assistant
                    }
                    return Message(role: role, content: m.content)
                }
                inputTokens = 0; outputTokens = 0; contextPct = 0
            } catch is CancellationError {
                // 20-second timeout fired or app backgrounded — show a clear message.
                errorMessage = "Request timed out. Check your connection and try again."
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URLSession cancelled by iOS lifecycle — not an error worth surfacing.
                return
            } catch {
                errorMessage = "Could not load messages (\(error.localizedDescription)). Check your connection and try again."
            }
        }
    }

    func deleteConversation(_ id: String) {
        Task {
            do {
                try await api.deleteConversation(id: id)
                await loadConversations()
                if id == currentConvId {
                    if let first = conversations.first {
                        selectConversation(first.id)
                    } else {
                        messages = []
                        currentConvId = ""
                        inputTokens = 0; outputTokens = 0; contextPct = 0
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameConversation(_ id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await api.renameConversation(id: id, title: trimmed)
                if let idx = conversations.firstIndex(where: { $0.id == id }) {
                    let old = conversations[idx]
                    conversations[idx] = Conversation(
                        id: old.id, title: trimmed,
                        createdAt: old.createdAt, updatedAt: old.updatedAt,
                        modelName: old.modelName, messageCount: old.messageCount,
                        projectId: old.projectId
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        // Same Task-based timeout pattern as selectConversation — see comment there.
        // 15 s gives the server room to respond even while inference is running.
        let work = Task { try await api.listConversations() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(15))
            work.cancel()
        }
        defer { timeout.cancel() }
        do {
            conversations = try await work.value
        } catch is CancellationError {
            // 8-second timeout fired (server busy or network slow) — don't surface
            // the raw "cancelled" description; show nothing so background refreshes
            // (e.g. after streaming) fail silently and a user-triggered pull-to-refresh
            // shows a friendlier message.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled by iOS when app went to background — ignore.
            return
        } catch {
            errorMessage = "Could not reach server (\(error.localizedDescription)). Check your connection and try again."
        }
    }

    // ── Event handler ─────────────────────────────────────────────────────────

    private func handle(event: ServerEvent, assistantMsgId: UUID) {
        lastEventDate = Date()  // any event (incl. heartbeat) resets the stale-connection clock

        switch event {

        case .thinking(let content):
            if thinkingContent == nil { thinkingContent = "" }
            thinkingContent? += content
            isThinkingActive = true
            if streamingWaitMessage != nil { streamingWaitMessage = "Thinking…" }

        case .token(let t):
            isThinkingActive = false
            if streamingWaitMessage != nil {
                streamingWaitMessage = nil
                waitMessageTask?.cancel()
                waitMessageTask = nil
            }
            bufferToken(t, msgId: assistantMsgId)

        case .searchStart(let q):
            currentSearchQuery = q

        case .searchDone:
            currentSearchQuery = nil

        case .fetchStart:
            isFetching = true

        case .fetchDone:
            break

        case .toolStart(_, let label):
            currentToolLabel = label

        case .toolDone:
            currentToolLabel = nil

        case .fetchContext(let fetches):
            isFetching = false
            updateMessage(id: assistantMsgId) { $0.fetchContext = fetches }

        case .ragContext(let chunks):
            updateMessage(id: assistantMsgId) { $0.ragContext = chunks }

        case .stats(let i, let o, let pct):
            // Assign through a local binding so the three writes reach the run-loop
            // in a single batch, preventing transient UI inconsistency.
            (inputTokens, outputTokens, contextPct) = (i, o, pct)

        case .done(let content):
            flushPendingTokens()
            updateMessage(id: assistantMsgId) { $0.content = content; $0.isStreaming = false }
            isStreaming = false
            currentSearchQuery = nil
            isFetching = false
            // loadConversations() is called in finishStreaming() after the loop,
            // which runs after .title and .compress events have also been processed.

        case .title(let convId, let title):
            receivedTitleDuringStream = true
            if currentConvId.isEmpty { currentConvId = convId }
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                let old = conversations[idx]
                conversations[idx] = Conversation(
                    id: old.id, title: title,
                    createdAt: old.createdAt, updatedAt: old.updatedAt,
                    modelName: old.modelName, messageCount: old.messageCount,
                    projectId: old.projectId
                )
            } else {
                Task { await loadConversations() }
            }

        case .compress(let msg):
            logger.info("History compressed: \(msg)")

        case .warning(let msg):
            errorMessage = "⚠️ \(msg)"

        case .error(let msg):
            errorMessage = msg
            isStreaming = false

        case .heartbeat:
            break

        default:
            break
        }
    }

    // ── Token throttle ────────────────────────────────────────────────────────

    private func bufferToken(_ token: String, msgId: UUID) {
        pendingTokenBuffer += token
        if flushTask == nil {
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.flushPendingTokens()
                self?.flushTask = nil
            }
        }
    }

    private func flushPendingTokens() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingTokenBuffer.isEmpty else { return }
        let buf = pendingTokenBuffer
        pendingTokenBuffer = ""
        if let idx = messages.indices.last, messages[idx].role == .assistant {
            messages[idx].content += buf
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func finishStreaming(msgId: UUID) {
        flushPendingTokens()
        updateMessage(id: msgId) { $0.isStreaming = false }
        isStreaming = false
        isThinkingActive = false
        currentToolLabel = nil
        streamingWaitMessage = nil
        waitMessageTask?.cancel()
        waitMessageTask = nil
        staleConnectionTask?.cancel()
        staleConnectionTask = nil

        // If the stream ended without a server .title event (timeout, network drop,
        // or error on the first message), use the user's prompt as a fallback title
        // so the conversation is identifiable in the sidebar.
        if !receivedTitleDuringStream, !pendingFirstMessage.isEmpty, !currentConvId.isEmpty {
            let fallback = String(pendingFirstMessage.prefix(60))
            renameConversation(currentConvId, title: fallback)
        }
        pendingFirstMessage = ""
        receivedTitleDuringStream = false

        // Always refresh the conversation list — on success to pick up the server
        // title, on error/timeout so the sidebar reflects current server state.
        Task { await loadConversations() }
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .resourceUnavailable,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    private func updateMessage(id: UUID, transform: (inout Message) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        transform(&messages[idx])
    }
}
