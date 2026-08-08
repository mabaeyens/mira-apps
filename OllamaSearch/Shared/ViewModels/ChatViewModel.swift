import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mab.mira", category: "ChatViewModel")

enum ThinkingMode: String, CaseIterable {
    case adaptive  // omit thinking_enabled — server heuristic decides
    case off       // send thinking_enabled = "false"
    case on        // send thinking_enabled = "true"

    mutating func cycle() {
        switch self {
        case .off:      self = .adaptive
        case .adaptive: self = .on
        case .on:       self = .off
        }
    }
}

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
    var thinkingMode: ThinkingMode = .adaptive
    var thinkingContent: String? = nil
    var isThinkingActive: Bool = false
    /// Empty until `/backend` answers. It used to default to "ollama", which
    /// meant the app asserted a backend it had not asked about yet.
    var currentBackend: String = ""
    var modelName: String = ""
    var backendPresets: [BackendPreset] = []
    /// The local model library from `GET /models`. Nil until it loads, or when
    /// the request failed; rows then render without a size rather than lying.
    var modelLibrary: ModelsResponse? = nil

    var modelDisplayName: String {
        // Strip org prefix and -it-* suffix: mlx-community/gemma-4-26b-a4b-it-4bit → gemma-4-26b-a4b
        let base = modelName.split(separator: "/").last.map(String.init) ?? modelName
        return base.components(separatedBy: "-it-").first ?? base
    }

    /// Label for the running backend, or an empty string before `/backend`
    /// answers. See `Backend` for why this is not a local switch any more.
    var backendDisplayName: String { Backend.label(for: currentBackend) }

    /// Best available name for whatever is serving: the model if known, else the
    /// backend, else a neutral word. Used in the status lines that used to read
    /// "Starting …" with nothing after the space.
    var runningLabel: String {
        if !modelName.isEmpty { return modelName }
        let backend = backendDisplayName
        return backend.isEmpty ? "the model" : backend
    }
    var contextWindow: Int = 0
    var isSwitchingBackend: Bool = false
    var showModelPicker: Bool = false
    var switchStatusMessage: String = ""
    var backendReady: Bool = true      // optimistic; polling corrects it
    var backendLoadingSince: Date? = nil  // set when backend_ready is first false after connect
    var isStartingBackend: Bool = false
    /// The server's advisory about its own machine's memory, from `GET /hardware`.
    ///
    /// **Advisory only.** Nothing about sending a message may ever consult this.
    /// The server deliberately refuses nothing on this basis, and if a memory
    /// advisory could stop the user talking to Mira then another app opening tabs
    /// could take Mira offline — a worse product than one slow reply.
    ///
    /// Starts `.unknown`, which renders as nothing, so a server that never
    /// reports one is indistinguishable from never having asked.
    private(set) var memoryAdvisory: MemoryAdvisory = .unknown
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
    var agentStepLabel: String? = nil

    var errorMessage: String? = nil

    // ── Destructive-action approvals ──────────────────────────────────────────
    // Queue of refused destructive actions awaiting a user decision; the sheet
    // shows `first`. A queue rather than a single value because one turn can
    // refuse several actions.
    var pendingApprovals: [PendingApproval] = []
    /// Tokens the user has explicitly approved, staged for the *next* request
    /// only. Deliberately a plain in-memory array: never persisted, never
    /// written from model output, and drained on read so a retry cannot reuse
    /// one. Populated solely by `approve(_:)`.
    private var approvedTokens: [String] = []

    /// Non-nil while a conversation's message history is being fetched.
    /// The value is the ID being loaded, used to show a per-row spinner.
    var loadingConvId: String? = nil
    /// True while the conversation list is being fetched from the server.
    var isLoadingConversations: Bool = false
    /// Non-nil when conversations are loaded from the iCloud cache (backend unreachable).
    var offlineCacheDate: Date? = nil

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
    private var streamEndedWithError = false
    // True once this conversation has at least one successfully saved exchange.
    // Used to decide whether to delete (never sent) or rename (failed send) on error.
    private var conversationHadSuccessfulSend = false

    // ── Slow-connection patience messages ─────────────────────────────────────
    // Shown after 3 s of streaming with no tokens yet. Rotates every 6 s.
    var streamingWaitMessage: String? = nil

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
            guard !currentConvId.isEmpty else {
                messages.append(.info("Nothing to compact yet."))
                return
            }
            Task {
                do {
                    let msg = try await api.compact(conversationId: currentConvId)
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

        // Drain: tokens ride exactly one request. A Resend after this point
        // carries none, which is the intended behaviour — re-approving is a tap.
        let tokens = approvedTokens
        approvedTokens = []

        // Capture image data for inline thumbnails before clearing attachments
        let imageData = attachments.compactMap { att -> Data? in
            if case .fileData(_, let data, let mime) = att, mime.hasPrefix("image/") { return data }
            return nil
        }
        let fileNames = attachments.compactMap { att -> String? in
            if case .fileData(let name, _, let mime) = att, !mime.hasPrefix("image/") { return name }
            return nil
        }

        // Track before appending: if no user messages exist yet, this is the first.
        // finishStreaming() uses this to auto-title the conversation when the server's
        // .title event never arrives (e.g. stream timed out).
        let isFirstMessage = !messages.contains(where: { $0.role == .user })
        pendingFirstMessage = isFirstMessage ? text : ""
        receivedTitleDuringStream = false

        // Add user bubble immediately
        messages.append(Message(role: .user, content: text, imageAttachments: imageData, attachedFileNames: fileNames))

        // Add an empty streaming assistant bubble
        let assistantMsg = Message(role: .assistant)
        messages.append(assistantMsg)

        isStreaming = true
        currentSearchQuery = nil
        isFetching = false
        currentToolLabel = nil
        agentStepLabel = nil
        thinkingContent = nil
        isThinkingActive = false
        streamEndedWithError = false

        streamingWaitMessage = "Sending…"

        // Reset heartbeat clock then start watchdog: if no event arrives for >15 s
        // (including heartbeats, which come every 5 s), treat as dropped connection.
        lastEventDate = Date()
        staleConnectionTask?.cancel()
        staleConnectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.isStreaming else { break }
                if Date().timeIntervalSince(self.lastEventDate) > 15 {
                    self.streamEndedWithError = true
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
            // Shrink oversized images before they are base64'd into the body.
            // Detached on purpose: this class is @MainActor, so resizing here
            // would block the UI, and it is a few hundred milliseconds on a
            // 12 MP photo. It runs after send() has already drawn the message,
            // so the cost is hidden behind the spinner rather than the tap.
            let payload = await Task.detached(priority: .userInitiated) {
                AttachmentImageDownscaler.downscaling(attachments)
            }.value
            guard !Task.isCancelled else { return }
            let request = self.api.chatRequest(
                message: text,
                conversationId: self.currentConvId,
                attachments: payload,
                thinkingMode: self.thinkingMode,
                approvedTokens: tokens
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
                self.streamEndedWithError = true
                self.errorMessage = Self.isNetworkError(error)
                    ? "Connection lost — the server may be sleeping. Tap Resend when it's back."
                    : error.localizedDescription
            }
            self.finishStreaming(msgId: assistantMsg.id)
        }
    }

    // ── Approvals ─────────────────────────────────────────────────────────────

    /// The user tapped Approve. Stages the token for the next request only.
    /// This is the ONLY path that may write `approvedTokens` — approval has to
    /// originate from a tap, or the gate is worthless.
    func approve(_ approval: PendingApproval) {
        pendingApprovals.removeAll { $0.id == approval.id }
        approvedTokens.append(approval.token)
        // Wait until every queued action has a decision, so one send carries them all.
        guard pendingApprovals.isEmpty else { return }
        // The user may have approved without typing anything; the model still
        // needs a turn in which to retry the action.
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = "approved"
        }
        send()
    }

    /// The user tapped Cancel. Drop the token and send nothing — the model
    /// already has the refusal in context.
    func decline(_ approval: PendingApproval) {
        pendingApprovals.removeAll { $0.id == approval.id }
    }

    /// Drop every pending approval and staged token. Called whenever the
    /// conversation changes so tokens cannot leak across conversations.
    private func clearApprovals() {
        pendingApprovals = []
        approvedTokens = []
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        staleConnectionTask?.cancel()
        staleConnectionTask = nil
        streamingWaitMessage = nil
        isThinkingActive = false
        isFetching = false
        currentToolLabel = nil
        // Store (don't fire-and-forget) so send() can await this before the next request.
        cancelTask = Task { [weak self] in
            guard let self else { return }
            await self.api.cancel(conversationId: self.currentConvId)
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

    /// Non-nil after any completed exchange (success or failure, not streaming).
    /// Used by resendLast() and editLast() for the bottom action bar.
    var lastUserMessage: Message? {
        guard !isStreaming,
              let last = messages.last, last.role == .assistant,
              messages.count >= 2,
              messages[messages.count - 2].role == .user
        else { return nil }
        return messages[messages.count - 2]
    }

    /// Drops the last exchange and re-sends the same question.
    func resendLast() {
        guard let userMsg = lastUserMessage else { return }
        let text = userMsg.content
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
        send()
    }

    /// Drops the last exchange and restores the question to the input field.
    func editLast() {
        guard let userMsg = lastUserMessage else { return }
        let text = userMsg.content
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
    }

    func prepareForNewConversation() {
        streamTask?.cancel()
        clearApprovals()
        currentConvId = ""
        messages = []
        inputTokens = 0; outputTokens = 0; contextPct = 0
    }

    func newConversation(projectId: String? = nil) {
        streamTask?.cancel()
        clearApprovals()
        thinkingMode = .adaptive
        let staleId = !currentConvId.isEmpty && !conversationHadSuccessfulSend ? currentConvId : nil
        conversationHadSuccessfulSend = false
        Task {
            if let id = staleId {
                try? await api.deleteConversation(id: id)
            }
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
        await loadBackendPresets()
    }

    func loadBackendPresets() async {
        do {
            backendPresets = try await APIClient.shared.fetchBackends()
        } catch {
            // Non-fatal — picker falls back to empty list
        }
        await loadModelLibrary()
    }

    /// What is actually on disk, used to put a size next to each row.
    /// `fetchModels()` had existed with no call site since it was written; the
    /// picker rendered mira.yaml instead and never asked what was installed.
    func loadModelLibrary() async {
        do {
            modelLibrary = try await APIClient.shared.fetchModels()
        } catch {
            // Non-fatal — rows simply show no size.
            modelLibrary = nil
        }
    }

    /// Check Mira health and update backendReady. Call once on connect, then poll.
    func refreshBackendHealth() async {
        let h = await APIClient.shared.health()
        switch h.startupStatus {
        case .ready:
            if h.backendReady {
                backendLoadingSince = nil
            } else if backendLoadingSince == nil {
                backendLoadingSince = Date()
            }
            backendReady = h.backendReady
        case .starting, .unavailable:
            backendReady = false
        }
    }

    /// Refresh the server's system-memory advisory.
    ///
    /// Best-effort in every direction: a failure here means "no information", so
    /// it resets to `.unknown` (which shows nothing) rather than leaving a stale
    /// warning on screen. It never surfaces an error to the user — a machine that
    /// cannot report its memory is not a problem the user has to hear about.
    func refreshMemoryAdvisory() async {
        do {
            let hw = try await APIClient.shared.fetchHardware()
            memoryAdvisory = hw.systemMemory?.advisory ?? .unknown
        } catch {
            memoryAdvisory = .unknown
        }
    }

    /// Start periodic backend health polling every 10 s (cancels on next call).
    private var healthPollTask: Task<Void, Never>?
    private var memoryPollTask: Task<Void, Never>?

    func startHealthPolling() {
        healthPollTask?.cancel()
        healthPollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Poll faster during startup so the loading banner clears promptly.
                let isReady = self?.backendReady ?? true
                let interval: Duration = isReady ? .seconds(10) : .seconds(3)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                await self?.refreshBackendHealth()
            }
        }

        // Separate loop on purpose: the advisory is re-derived server-side every
        // 30s, so polling it on the 10s health cadence would spend three requests
        // to read the same value. Folded into this method rather than given its
        // own start call so it shares one lifecycle with health polling.
        memoryPollTask?.cancel()
        memoryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMemoryAdvisory()
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
            }
        }
    }

    /// Tell the server to start its configured inference backend.
    func startBackend() async {
        guard !isStartingBackend, !isSwitchingBackend else { return }
        isStartingBackend = true
        switchStatusMessage = "Starting \(runningLabel)…"
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

        let toBackendLabel = Backend.label(for: backend)
        switchStatusMessage = "Stopping \(runningLabel)…"

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
            if !currentConvId.isEmpty {
                messages.append(.info("— Switched to \(info.model) (\(Backend.label(for: info.backend))). Conversation history is preserved. —"))
            }
            await loadBackendPresets()
        } catch {
            statusTask.cancel()
            errorMessage = "Failed to switch model: \(error.localizedDescription)"
        }
        switchStatusMessage = ""
        isSwitchingBackend = false
    }

    func switchModel(backend: String, modelId: String) async {
        guard !isSwitchingBackend else { return }
        isSwitchingBackend = true

        let toLabel = modelId.split(separator: "/").last.map(String.init) ?? modelId
        switchStatusMessage = "Stopping \(runningLabel)…"

        let statusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Starting \(toLabel)…"
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Loading model weights…"
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            switchStatusMessage = "Almost ready…"
        }

        do {
            let info = try await APIClient.shared.switchModel(backend: backend, modelId: modelId)
            statusTask.cancel()
            currentBackend = info.backend
            modelName = info.model
            contextWindow = info.contextWindow
            showModelPicker = false
            if !currentConvId.isEmpty {
                messages.append(.info("— Switched to \(info.model) (\(Backend.label(for: info.backend))). Conversation history is preserved. —"))
            }
            await loadBackendPresets()
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
        clearApprovals()
        // Delete the current conversation if it was never sent — it would stay as
        // an empty "New conversation" entry otherwise.
        let staleId = !currentConvId.isEmpty && !conversationHadSuccessfulSend && id != currentConvId
            ? currentConvId : nil
        conversationHadSuccessfulSend = false
        loadingConvId = id
        Task {
            if let sid = staleId {
                try? await api.deleteConversation(id: sid)
            }
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
                    return Message(role: role, content: m.content,
                                   thinkingContent: m.thinkingContent)
                }
                conversationHadSuccessfulSend = !messages.isEmpty
                thinkingContent = messages.last(where: { $0.role == .assistant })?.thinkingContent
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

    /// File a conversation under a project, or unfile it with `projectId: nil`.
    ///
    /// Both lists have to be refreshed: `conversations` because the sidebar
    /// groups by project and the row has to move, `projects` because the row
    /// carries a conversation count. Refreshing only the first leaves the count
    /// stale, which is the bug already sitting in `backlog.md` under "Project
    /// conversation count".
    func setProject(_ projectId: String?, for conversationId: String) {
        guard !conversationId.isEmpty else { return }
        Task {
            do {
                try await api.setConversationProject(id: conversationId, projectId: projectId)
                await loadConversations()
                await loadProjects()
            } catch {
                errorMessage = "Could not move the conversation: \(error.localizedDescription)"
            }
        }
    }

    func deleteConversation(_ id: String) {
        Task {
            do {
                try await api.deleteConversation(id: id)
                await loadConversations()
                await loadProjects()
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
            offlineCacheDate = nil
            Task { await ConversationCache.shared.save(conversations) }
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
            if let cached = await ConversationCache.shared.load(), !cached.conversations.isEmpty {
                conversations = cached.conversations
                offlineCacheDate = cached.savedAt
            } else {
                errorMessage = "Could not reach server (\(error.localizedDescription)). Check your connection and try again."
            }
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

        case .agentStep(let step, let tool):
            agentStepLabel = "Step \(step)/15 · \(tool)"

        case .approvalRequired(let approval):
            // Ignore a repeat of an action already queued — the server can refuse
            // the same command twice in one turn.
            guard !pendingApprovals.contains(where: { $0.token == approval.token }) else { break }
            pendingApprovals.append(approval)

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
            streamingWaitMessage = nil
            currentSearchQuery = nil
            isFetching = false
            agentStepLabel = nil
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
        agentStepLabel = nil
        streamingWaitMessage = nil
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

        if streamEndedWithError, !currentConvId.isEmpty {
            streamEndedWithError = false
            let isNewConv = !conversationHadSuccessfulSend
            if isNewConv {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                let time = formatter.string(from: Date())
                renameConversation(currentConvId, title: "Pending – Retry \(time)")
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.errorMessage = nil
                if let history = try? await self.api.getMessages(conversationId: self.currentConvId), !history.isEmpty {
                    self.messages = history.map { m in
                        let role: Message.Role = m.role == "user" ? .user : .assistant
                        return Message(role: role, content: m.content,
                                       thinkingContent: m.thinkingContent)
                    }
                    self.thinkingContent = self.messages.last(where: { $0.role == .assistant })?.thinkingContent
                }
            }
        } else {
            conversationHadSuccessfulSend = true
        }
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
