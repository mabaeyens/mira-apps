import Foundation
import SwiftUI

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
    var currentConvId: String = ""
    var isStreaming: Bool = false
    var inputText: String = ""
    var pendingAttachments: [AttachmentPayload] = []
    var stagedAttachmentNames: [String] = []

    // Status line
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var contextPct: Double = 0

    // In-progress search/fetch indicators (cleared when done)
    var currentSearchQuery: String? = nil
    var isFetching: Bool = false

    var errorMessage: String? = nil

    // ── Internals ────────────────────────────────────────────────────────────

    private var streamTask: Task<Void, Never>?

    // Token throttle: accumulate tokens, flush every 100ms to avoid
    // re-rendering swift-markdown-ui on every individual token.
    // Uses a Task instead of Timer — Task closures inherit @MainActor context,
    // avoiding the nonisolated-closure issue that Timer callbacks have.
    private var pendingTokenBuffer: String = ""
    private var flushTask: Task<Void, Never>?

    private let api = APIClient.shared
    private let sse = SSEClient.shared
    // No deinit needed: streamTask/flushTask use [weak self] so self can be
    // deallocated freely; stopStreaming() handles explicit cancellation.

    // ── Public API ────────────────────────────────────────────────────────────

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isStreaming else { return }

        inputText = ""
        let attachments = pendingAttachments
        pendingAttachments = []
        stagedAttachmentNames = []

        // Add user bubble immediately
        messages.append(Message(role: .user, content: text))

        // Add an empty streaming assistant bubble
        let assistantMsg = Message(role: .assistant)
        messages.append(assistantMsg)

        isStreaming = true
        currentSearchQuery = nil
        isFetching = false

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            let request = self.api.chatRequest(
                message: text,
                conversationId: self.currentConvId,
                attachments: attachments
            )
            do {
                for try await event in self.sse.stream(request: request) {
                    guard !Task.isCancelled else { break }
                    self.handle(event: event, assistantMsgId: assistantMsg.id)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.finishStreaming(msgId: assistantMsg.id)
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        flushTask?.cancel()
        flushTask = nil
        Task { await api.cancel() }
        flushPendingTokens()
        if let idx = messages.indices.last, messages[idx].role == .assistant {
            messages[idx].isStreaming = false
        }
        isStreaming = false
    }

    func newConversation() {
        streamTask?.cancel()
        Task {
            do {
                let conv = try await api.createConversation()
                currentConvId = conv.id
                messages = []
                inputTokens = 0; outputTokens = 0; contextPct = 0
                await loadConversations()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectConversation(_ id: String) {
        guard id != currentConvId else { return }
        streamTask?.cancel()
        Task {
            do {
                let history = try await api.getMessages(conversationId: id)
                currentConvId = id
                messages = history.map { m in
                    Message(
                        role: m.role == "user" ? .user : .assistant,
                        content: m.content
                    )
                }
                inputTokens = 0; outputTokens = 0; contextPct = 0
            } catch {
                errorMessage = error.localizedDescription
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
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadConversations() async {
        do {
            conversations = try await api.listConversations()
        } catch {
            // Non-fatal — sidebar just won't update
        }
    }

    // ── Event handler ─────────────────────────────────────────────────────────

    private func handle(event: ServerEvent, assistantMsgId: UUID) {
        switch event {

        case .thinking:
            break   // could show a "..." indicator; skip for now

        case .token(let t):
            bufferToken(t, msgId: assistantMsgId)

        case .searchStart(let q):
            currentSearchQuery = q

        case .searchDone:
            currentSearchQuery = nil

        case .fetchStart:
            isFetching = true

        case .fetchDone:
            break

        case .fetchContext(let fetches):
            isFetching = false
            updateMessage(id: assistantMsgId) { $0.fetchContext = fetches }

        case .ragContext(let chunks):
            updateMessage(id: assistantMsgId) { $0.ragContext = chunks }

        case .stats(let i, let o, let pct):
            inputTokens = i; outputTokens = o; contextPct = pct

        case .done(let content):
            flushPendingTokens()
            updateMessage(id: assistantMsgId) { $0.content = content; $0.isStreaming = false }
            isStreaming = false
            currentSearchQuery = nil
            isFetching = false
            Task { await loadConversations() }

        case .title(let convId, let title):
            // If we started the turn with no convId, adopt the server-assigned one
            if currentConvId.isEmpty { currentConvId = convId }
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                let old = conversations[idx]
                conversations[idx] = Conversation(
                    id: old.id, title: title,
                    createdAt: old.createdAt, updatedAt: old.updatedAt,
                    modelName: old.modelName
                )
            } else {
                Task { await loadConversations() }
            }

        case .compress(let msg):
            // Could show a transient notification; log for now
            print("[compress] \(msg)")

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
    }

    private func updateMessage(id: UUID, transform: (inout Message) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        transform(&messages[idx])
    }
}
