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

/// What the message area knows about the conversation on screen. The area is
/// never empty: with no messages to show it renders `.loading` as a spinner and
/// `.failed` as an error with Retry, and only `.idle` as the empty conversation.
enum TranscriptLoad: Equatable {
    case idle
    /// Nothing to show yet; the server copy is on its way.
    case loading(since: Date)
    /// A saved copy is on screen; the server copy is on its way.
    case refreshing(since: Date)
    /// Nothing to show, and the fetch failed.
    case failed(String)
    /// A saved copy is on screen, and the refresh failed.
    case stale(String)

    var isInFlight: Bool {
        switch self {
        case .loading, .refreshing: return true
        default: return false
        }
    }
}

/// Where the last sent turn stands. Drives the status line above the input bar.
enum TurnPhase: Equatable {
    case idle
    /// The request is open: sending, waking, thinking or receiving tokens.
    case streaming(since: Date)
    /// The stream ended without the reply finishing. The server goes on writing
    /// it, so the app polls until the saved reply shows up. `reached` is false
    /// when not one event came back, so the request may never have arrived.
    case awaitingReply(since: Date, reached: Bool)
    /// The finished reply was reloaded from the server.
    case restored(at: Date)
    /// The poll ran out without finding the reply.
    case unrecovered(reached: Bool)

    /// A turn is running or awaited: its conversation must not be deleted.
    var isLive: Bool {
        switch self {
        case .streaming, .awaitingReply: return true
        default: return false
        }
    }
}

/// One line of status for the chat screen. A pure function of the view model's
/// state and the clock; `ChatViewModel.statusLine(now:)` builds it every second.
struct ChatStatusLine: Equatable {
    enum Tone { case progress, warning, success, failure }
    enum Action { case retryLoad, checkAgain, stopWaiting }
    let text: String
    let tone: Tone
    var showsSpinner: Bool = false
    var action: Action? = nil
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
    /// Why the last `/backends` request failed, or nil. The picker shows this
    /// instead of claiming mira.yaml has no entries.
    var backendPresetsError: String? = nil
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
    /// Engine lifecycle state from `/health`; nil when the server's lifecycle is off.
    var engineState: String? = nil
    private var isWakingEngine = false
    var isEngineAsleep: Bool { engineState == "sleeping" }
    var isEngineWaking: Bool { engineState == "waking" }
    /// What the engine-lifecycle banner should say, or nil when there is nothing to show.
    var engineBanner: (text: String, spinner: Bool)? {
        switch engineState {
        case "waking":    return ("Waking up…", true)
        case "unloading": return ("Unloading…", true)
        case "sleeping":  return ("Asleep. Wakes when you send a message.", false)
        default:          return nil
        }
    }
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
    /// Not observed: it changes on every event, and the status line reads it on
    /// its own one-second tick.
    @ObservationIgnored private var lastEventDate = Date.distantPast
    /// True while a turn is waiting on a sleeping or waking engine. The server
    /// holds /chat until the engine is up (9-25 s typical, ~260 s worst case) and
    /// sends nothing meanwhile, so the 15 s silence rule would cancel every slow
    /// wake. Cleared by the first event of the turn.
    private var wakeGrace = false
    /// Silence limit in seconds. `-MiraStaleSeconds <n>` on the launch line
    /// overrides the normal 15 so a UI test can force the watchdog to trip
    /// during a wake without needing a slow one.
    private static let staleLimit: TimeInterval = {
        let override = UserDefaults.standard.integer(forKey: "MiraStaleSeconds")
        return override > 0 ? TimeInterval(override) : 15
    }()
    private static let wakeGraceLimit: TimeInterval = 300

    // ── What is on screen, and what the last turn is doing ────────────────────

    /// Identity of the transcript on screen. Changes when a different
    /// conversation (or a new, empty one) is put on screen, and at no other
    /// time. ChatView uses it as the identity of the message list, so each
    /// conversation gets its own scroll position and nothing else rebuilds it.
    private(set) var transcriptID = UUID()
    private(set) var transcriptLoad: TranscriptLoad = .idle
    private(set) var turnPhase: TurnPhase = .idle

    /// The turn that was sent and has not been seen to finish. It outlives the
    /// stream: after a drop, and after the user leaves the conversation, the
    /// server is still writing the reply and `awaitReply()` is still looking
    /// for it.
    private struct PendingTurn {
        /// The transcript it was sent from; equal to `transcriptID` while that
        /// transcript is the one on screen.
        var transcript: UUID
        /// Empty for a new conversation until the server names it. The id comes
        /// with the title, at the end of the turn, so a drop leaves it unknown.
        var convId: String
        let text: String
        let sentAt: Date
        /// Copies of `text` among the user messages before this send. The turn
        /// is saved once the server holds one more.
        let priorCopies: Int
        /// What was on screen when the user left, to put back if they return.
        var snapshot: [Message] = []
    }
    private var pendingTurn: PendingTurn?
    private var awaitTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// Bumped whenever the running stream stops being the one that counts (Stop,
    /// a watchdog trip, leaving the conversation, the next send). The stream
    /// task checks it before touching any state, so a stream that was let go
    /// cannot write into whatever is on screen now.
    private var streamGeneration = 0
    /// The `done` event arrived: the server finished the reply.
    private var turnCompleted = false
    /// The server said the turn failed (an `error` event or an HTTP error), so
    /// there is no reply to wait for.
    private var turnFailedOnServer = false
    /// At least one event came back, so the request reached the server.
    private var turnReachedServer = false
    /// Take the server's copy of the history once the running turn ends: set
    /// when the turn started on a transcript that may differ from the server's.
    private var reloadAfterTurn = false

    /// Transcripts already seen this session, newest last, so reopening one
    /// paints in the same frame. `TranscriptCache` is the copy that survives a
    /// relaunch.
    private var transcriptMemory: [String: [Message]] = [:]
    private var transcriptMemoryOrder: [String] = []
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

    // True while a turn sent with `retry=true` is in flight, so finishStreaming()
    // knows to take the server's copy of the history rather than trusting the two
    // messages resendLast() trimmed locally. See reloadHistoryFromServer().
    private var retryInFlight: Bool = false

    private let api = APIClient.shared
    private let sse = SSEClient.shared
    // No deinit needed: streamTask/flushTask use [weak self] so self can be
    // deallocated freely; stopStreaming() handles explicit cancellation.

    // ── Public API ────────────────────────────────────────────────────────────

    /// `retry` is set only by `resendLast()`. It reaches the server as a form
    /// field that deletes the previous turn before this one starts, so it must
    /// never be inferred — asking the same question twice on purpose is a
    /// legitimate thing to do and must not silently eat history.
    func send(retry: Bool = false) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isStreaming else { return }
        // The previous reply in this conversation is still being waited for. A
        // second turn now would run on a history without it, and in a new
        // conversation (no id yet) it would start a second one.
        if turnPhase.isLive, pendingTurnIsOnScreen {
            errorMessage = "Still waiting for the previous reply. Tap Stop waiting to send this now."
            return
        }

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

        // Sending onto a transcript that may not match the server's (a refresh
        // still in flight or failed, or an earlier turn still unaccounted for):
        // take the server's copy when this turn ends.
        var earlierTurnUnaccounted = turnPhase.isLive
        if case .unrecovered = turnPhase { earlierTurnUnaccounted = true }
        reloadAfterTurn = transcriptLoad != .idle || earlierTurnUnaccounted
        if transcriptLoad != .idle {
            loadTask?.cancel()
            loadingConvId = nil
            transcriptLoad = .idle
        }
        awaitTask?.cancel()
        let sentAt = Date()
        pendingTurn = PendingTurn(
            transcript: transcriptID,
            convId: currentConvId,
            text: text,
            sentAt: sentAt,
            priorCopies: messages.filter { $0.role == .user && $0.content == text }.count
        )
        turnPhase = .streaming(since: sentAt)
        turnCompleted = false
        turnFailedOnServer = false
        turnReachedServer = false
        streamGeneration += 1
        let generation = streamGeneration

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
        retryInFlight = retry

        streamingWaitMessage = (isEngineAsleep || isEngineWaking) ? "Waking up Mira…" : "Sending…"

        // Reset heartbeat clock then start watchdog: if no event arrives for >15 s
        // (including heartbeats, which come every 5 s), treat as dropped connection.
        lastEventDate = Date()
        // Lifecycle on (state non-nil) and the engine not running: the server will
        // wake it while holding this request. The cached state can be up to 10 s
        // stale (it may have unloaded since the last poll), so also re-check now.
        wakeGrace = engineState != nil && engineState != "running"
        if engineState != nil {
            Task { await refreshBackendHealth() }
        }
        staleConnectionTask?.cancel()
        staleConnectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.staleLimit < 5 ? Self.staleLimit : 5))
                guard let self, !Task.isCancelled, self.isStreaming,
                      self.streamGeneration == generation else { break }
                if let state = self.engineState, state != "running" { self.wakeGrace = true }
                let limit = self.wakeGrace ? Self.wakeGraceLimit : Self.staleLimit
                if Date().timeIntervalSince(self.lastEventDate) > limit {
                    // The connection went silent (Wi-Fi off, a dead tunnel). Let
                    // go of the stream locally and wait for the reply instead.
                    // No `/cancel`: the server is still writing the reply, and
                    // cancelling would throw away the turn this is about to wait
                    // for. With an unknown conversation id it would also cancel
                    // every other turn on the server.
                    self.endStreamLocally()
                    self.beginAwaitingReply()
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
            guard !Task.isCancelled, self.streamGeneration == generation else { return }
            // Shrink oversized images before they are base64'd into the body.
            // Detached on purpose: this class is @MainActor, so resizing here
            // would block the UI, and it is a few hundred milliseconds on a
            // 12 MP photo. It runs after send() has already drawn the message,
            // so the cost is hidden behind the spinner rather than the tap.
            let payload = await Task.detached(priority: .userInitiated) {
                AttachmentImageDownscaler.downscaling(attachments)
            }.value
            guard !Task.isCancelled, self.streamGeneration == generation else { return }
            let request = self.api.chatRequest(
                message: text,
                conversationId: self.currentConvId,
                attachments: payload,
                thinkingMode: self.thinkingMode,
                approvedTokens: tokens,
                retry: retry
            )
            do {
                for try await event in self.sse.stream(request: request) {
                    // A stream that was let go (Stop, a watchdog trip, leaving the
                    // conversation, the next send) must not write into whatever
                    // is on screen now.
                    guard !Task.isCancelled, self.streamGeneration == generation else { return }
                    self.handle(event: event, assistantMsgId: assistantMsg.id)
                }
            } catch is CancellationError {
                // The system took the connection (the app went to the background).
                // Not an error to report, but the reply is unfinished: see below.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Same, reported by URLSession.
            } catch {
                // A network failure is a drop, and the status line reports it. Any
                // other failure is the server refusing or failing the turn, so
                // there is no reply to wait for and the reason is worth an alert.
                if self.streamGeneration == generation, !Self.isNetworkError(error) {
                    self.turnFailedOnServer = true
                    self.errorMessage = error.localizedDescription
                }
            }
            guard self.streamGeneration == generation else { return }
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

    /// The user tapped Stop. The only path that tells the server to stop: it
    /// posts `/cancel`, and the server then saves nothing for the turn, so
    /// there is no reply to wait for.
    func stopStreaming() {
        let convId = pendingTurn?.convId ?? currentConvId
        endStreamLocally()
        awaitTask?.cancel()
        pendingTurn = nil
        turnPhase = .idle
        // Store (don't fire-and-forget) so send() can await this before the next request.
        cancelTask = Task { [weak self] in
            guard let self else { return }
            await self.api.cancel(conversationId: convId)
        }
    }

    /// Lets go of the running stream without telling the server anything. The
    /// server carries on and saves the reply; what happens next (wait for it, or
    /// nothing) is the caller's decision.
    private func endStreamLocally() {
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        staleConnectionTask?.cancel()
        staleConnectionTask = nil
        wakeGrace = false
        streamingWaitMessage = nil
        isThinkingActive = false
        isFetching = false
        currentSearchQuery = nil
        currentToolLabel = nil
        agentStepLabel = nil
        flushPendingTokens()
        if let idx = messages.indices.last, messages[idx].role == .assistant {
            messages[idx].isStreaming = false
        }
        isStreaming = false
        // This skips finishStreaming(), so clear the flag here too — it must
        // not survive into a later turn that was never a retry.
        retryInFlight = false
        pendingFirstMessage = ""
        receivedTitleDuringStream = false
    }

    /// Stop polling for a reply that is not coming. Sends nothing to the server.
    func stopWaitingForReply() {
        awaitTask?.cancel()
        pendingTurn = nil
        turnPhase = .idle
    }

    /// Look again for the reply after the poll gave up.
    func checkAgainForReply() {
        guard pendingTurn != nil, !isStreaming else { return }
        beginAwaitingReply()
    }

    /// Non-nil when the last exchange failed (empty assistant response, not streaming).
    /// Used to show the Resend / Edit buttons on the last user bubble.
    var lastFailedUserMessage: Message? {
        // Not failed while the reply is still being waited for.
        guard !isStreaming, !turnPhase.isLive,
              let last = messages.last, last.role == .assistant, last.content.isEmpty,
              messages.count >= 2,
              messages[messages.count - 2].role == .user
        else { return nil }
        return messages[messages.count - 2]
    }

    /// Non-nil after any completed exchange (success or failure, not streaming).
    /// Used by resendLast() and editLast() for the bottom action bar.
    var lastUserMessage: Message? {
        guard !isStreaming, !turnPhase.isLive,
              let last = messages.last, last.role == .assistant,
              messages.count >= 2,
              messages[messages.count - 2].role == .user
        else { return nil }
        return messages[messages.count - 2]
    }

    /// Drops the last exchange and re-sends the same question.
    ///
    /// The local trim is optimistic UI only. What actually replaces the turn is
    /// the `retry` flag on the request: the server drops the last user row and
    /// everything saved after it, under the conversation lock, before the new
    /// turn starts. Without the flag `save_messages` appends and the question
    /// ends up in the database twice with the broken answer between them, which
    /// every later turn is then built on.
    ///
    /// The flag is skipped on a conversation the server has not seen yet — there
    /// is no previous turn to replace, and an empty id makes the server create a
    /// fresh conversation that ignores it anyway.
    func resendLast() {
        guard let userMsg = lastUserMessage else { return }
        let text = userMsg.content
        // Not either when the last turn was never seen to be saved (the poll for
        // it gave up): the server's last user row is then most likely the turn
        // before, and the flag would delete that one. Sending without it risks
        // the question twice on the server, which loses nothing.
        let replacesServerTurn = !currentConvId.isEmpty && pendingTurn == nil
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
        send(retry: replacesServerTurn)
    }

    /// Drops the last exchange and restores the question to the input field.
    func editLast() {
        guard let userMsg = lastUserMessage else { return }
        let text = userMsg.content
        if messages.count >= 2 { messages.removeLast(2) }
        inputText = text
    }

    func prepareForNewConversation() {
        leaveTranscript()
        currentConvId = ""
        messages = []
        thinkingContent = nil
        inputTokens = 0; outputTokens = 0; contextPct = 0
    }

    /// Called before a different transcript goes on screen. Never deletes and
    /// never cancels anything on the server.
    ///
    /// A turn that is still streaming is let go locally and then waited for in
    /// the background: the server finishes it regardless, and the conversation
    /// has to be whole when the user comes back to it. A turn already being
    /// waited for just keeps being waited for.
    private func leaveTranscript() {
        if isStreaming {
            endStreamLocally()
            pendingTurn?.snapshot = messages
            beginAwaitingReply()
        } else if turnPhase.isLive {
            pendingTurn?.snapshot = messages
        } else {
            // Restored or given up: the line has been read, or no longer applies.
            if case .unrecovered = turnPhase { pendingTurn = nil }
            turnPhase = .idle
        }
        loadTask?.cancel()
        loadTask = nil
        loadingConvId = nil
        transcriptLoad = .idle
        clearApprovals()
        conversationHadSuccessfulSend = false
        transcriptID = UUID()
    }

    /// True while the turn in `pendingTurn` belongs to the transcript on screen.
    private var pendingTurnIsOnScreen: Bool {
        pendingTurn?.transcript == transcriptID
    }

    /// A conversation may be deleted on navigating away only if nothing was ever
    /// sent in it. "No successful send yet" is not enough: a first turn that is
    /// still running, or was cut by a dropped connection while the server finishes
    /// it, has no successful send either, and deleting it threw away the reply the
    /// server was about to save.
    ///
    /// It must also be a conversation this app instance created. An empty
    /// conversation that was merely opened may be one another client is writing
    /// its first turn into (the server saves nothing until the turn ends), and
    /// opening it and leaving used to delete it.
    private func isDiscardable() -> Bool {
        !currentConvId.isEmpty
            && currentConvId == createdHereConvId
            && !conversationHadSuccessfulSend
            && !messages.contains(where: { $0.role == .user })
    }

    /// The id `newConversation()` last created on the server, the only kind of
    /// conversation `isDiscardable()` may ever name.
    private var createdHereConvId: String?

    func newConversation(projectId: String? = nil) {
        thinkingMode = .adaptive
        let staleId = isDiscardable() ? currentConvId : nil
        // The empty conversation goes on screen now, not when the server has
        // answered: the old transcript must not sit there looking current.
        prepareForNewConversation()
        let transcript = transcriptID
        Task {
            if let id = staleId {
                try? await api.deleteConversation(id: id)
            }
            do {
                let convId = try await api.createConversation(projectId: projectId)
                createdHereConvId = convId
                // Still the empty conversation this call put up, and nothing
                // sent from it yet (a send with no id makes the server create one).
                if transcript == transcriptID, currentConvId.isEmpty, !isStreaming, messages.isEmpty {
                    currentConvId = convId
                } else {
                    // Created a moment ago, never shown and never sent to.
                    try? await api.deleteConversation(id: convId)
                }
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
            backendPresetsError = nil
        } catch {
            // Non-fatal, but say why: an empty list from a 401 is not an empty yaml.
            backendPresetsError = error.localizedDescription
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
            engineState = h.engineState
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

    // ── Engine lifecycle (mira-core idle unload) ──────────────────────────────

    /// Wake the engine so the load overlaps with typing. Only fires when the
    /// server reports `sleeping`; a no-op when the lifecycle is off (nil state).
    func wakeEngineIfNeeded() {
        // `-MiraNoAutoWake 1` on the launch line: a UI test that only reads stored
        // conversations must not load a model on a server other sessions share.
        guard !UserDefaults.standard.bool(forKey: "MiraNoAutoWake") else { return }
        guard engineState == "sleeping", !isWakingEngine else { return }
        isWakingEngine = true
        engineState = "waking"
        Task {
            await APIClient.shared.wakeEngine()
            isWakingEngine = false
            await refreshBackendHealth()
        }
    }

    /// Unload the engine now to free RAM. Returns a short message on failure.
    func unloadEngine() async -> String? {
        do {
            try await APIClient.shared.unloadEngine()
            await refreshBackendHealth()
            return nil
        } catch APIClient.EngineError.busyOrDisabled {
            return "Busy, or idle unload is off"
        } catch {
            return "Could not unload"
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

    /// Puts conversation `id` on screen at once, from whatever copy is at hand,
    /// and refreshes it from the server behind that.
    ///
    /// It used to await the server (up to 60 s) before showing anything. Now the
    /// conversation is current from the tap: a copy seen this session paints in
    /// the same frame, a copy on disk a moment later, and with neither the
    /// message area shows a spinner with text. A failed fetch leaves the saved
    /// copy up and says so, or shows an error with Retry when there is none.
    func selectConversation(_ id: String) {
        guard !id.isEmpty else { return }
        if id == currentConvId {
            // Already on screen. Only worth doing again when there is nothing
            // to show and nothing in flight (Retry after a failed load).
            guard messages.isEmpty, !transcriptLoad.isInFlight, !isStreaming else { return }
        }
        // Delete the conversation being left only if this app created it and
        // nothing was ever sent in it — see isDiscardable().
        let staleId = (isDiscardable() && id != currentConvId) ? currentConvId : nil
        leaveTranscript()
        currentConvId = id
        thinkingContent = nil
        inputTokens = 0; outputTokens = 0; contextPct = 0
        wakeEngineIfNeeded()
        if let staleId {
            Task { try? await api.deleteConversation(id: staleId) }
        }

        // Its turn is still being waited for: put back what was on screen when
        // the user left. The server has not saved that turn yet, so its copy
        // would take the question off the screen again.
        if let turn = pendingTurn, turnPhase.isLive, !turn.convId.isEmpty, turn.convId == id {
            pendingTurn?.transcript = transcriptID
            messages = turn.snapshot
            showLastThinking()
            return
        }

        if let known = transcriptMemory[id], !known.isEmpty {
            messages = known
            showLastThinking()
            transcriptLoad = .refreshing(since: Date())
        } else {
            messages = []
            transcriptLoad = .loading(since: Date())
        }
        startLoadingTranscript(id)
    }

    /// Retry after a failed load or refresh of the conversation on screen.
    func retryLoad() {
        guard !currentConvId.isEmpty, !transcriptLoad.isInFlight, !isStreaming, !turnPhase.isLive else { return }
        transcriptLoad = messages.isEmpty ? .loading(since: Date()) : .refreshing(since: Date())
        startLoadingTranscript(currentConvId)
    }

    private func startLoadingTranscript(_ id: String) {
        loadingConvId = id
        let transcript = transcriptID
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadTranscript(id: id, transcript: transcript)
        }
    }

    private func loadTranscript(id: String, transcript: UUID) async {
        defer { if transcript == transcriptID { loadingConvId = nil } }

        // The copy on disk, when this session has not seen the conversation yet.
        if messages.isEmpty, let saved = await TranscriptCache.shared.load(id), !saved.isEmpty {
            guard transcript == transcriptID, transcriptLoad.isInFlight else { return }
            if messages.isEmpty {
                messages = saved.map {
                    Message(role: $0.role == "user" ? .user : .assistant, content: $0.content,
                            thinkingContent: $0.thinkingContent)
                }
                showLastThinking()
                transcriptLoad = .refreshing(since: Date())
            }
        }
        guard transcript == transcriptID, !Task.isCancelled else { return }

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
        let outcome: Result<[ConversationMessage], Error>
        do {
            outcome = .success(try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            })
        } catch {
            outcome = .failure(error)
        }

        // Superseded: another conversation is on screen by now, or a message
        // was sent from this one (send() takes the server's copy afterwards).
        guard transcript == transcriptID, transcriptLoad.isInFlight else { return }
        switch outcome {
        case .success(let history):
            messages = merged(history)
            showLastThinking()
            conversationHadSuccessfulSend = !messages.isEmpty
            transcriptLoad = .idle
            rememberTranscript()
        case .failure(let error):
            let reason = Self.loadFailureReason(error)
            transcriptLoad = messages.isEmpty ? .failed(reason) : .stale(reason)
        }
    }

    private static func loadFailureReason(_ error: Error) -> String {
        if error is CancellationError { return "The server did not answer within 60 seconds." }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return "The request was interrupted."
        }
        return error.localizedDescription
    }

    /// The server's history as messages, keeping the message already on screen
    /// wherever it is the same one. Rows keep their identity that way, so a
    /// refresh that changes nothing redraws nothing, and locally attached
    /// thumbnails and file names (which the server does not store) survive it.
    private func merged(_ history: [ConversationMessage]) -> [Message] {
        let current = messages.filter { $0.role != .info }
        return history.enumerated().map { index, m in
            let role: Message.Role = m.role == "user" ? .user : .assistant
            if index < current.count, current[index].role == role,
               current[index].content == m.content, !current[index].isStreaming {
                var kept = current[index]
                if let thinking = m.thinkingContent { kept.thinkingContent = thinking }
                return kept
            }
            return Message(role: role, content: m.content, thinkingContent: m.thinkingContent)
        }
    }

    private func showLastThinking() {
        thinkingContent = messages.last(where: { $0.role == .assistant })?.thinkingContent
    }

    // ── Saved transcripts ─────────────────────────────────────────────────────

    /// Save what is on screen as the last known transcript of this conversation.
    /// Call only where the screen and the server agree: after a fetch, after a
    /// turn that finished, after a recovered reply.
    private func rememberTranscript() {
        remember(messages, for: currentConvId)
    }

    private func remember(_ transcript: [Message], for id: String) {
        let stable = transcript.filter { $0.role != .info && !$0.isStreaming }
        guard !id.isEmpty, !stable.isEmpty else { return }
        transcriptMemory[id] = stable
        transcriptMemoryOrder.removeAll { $0 == id }
        transcriptMemoryOrder.append(id)
        while transcriptMemoryOrder.count > 12 {
            transcriptMemory[transcriptMemoryOrder.removeFirst()] = nil
        }
        let entries = stable.map {
            TranscriptCache.Entry(role: $0.role == .user ? "user" : "assistant",
                                  content: $0.content, thinkingContent: $0.thinkingContent)
        }
        Task { await TranscriptCache.shared.save(entries, for: id) }
    }

    private func forgetTranscript(_ id: String) {
        transcriptMemory[id] = nil
        transcriptMemoryOrder.removeAll { $0 == id }
        Task { await TranscriptCache.shared.remove(id) }
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

    /// Why conversation `id` must not be deleted right now, or nil.
    ///
    /// A turn that is running or awaited exists only on its way to the server's
    /// database: the server saves a turn when it ends, so until then the
    /// conversation looks empty, and deleting it throws the reply away. For a
    /// new conversation the id is not known yet either, so any empty
    /// conversation created since the send counts as possibly that one.
    func deletionBlockedReason(for id: String) -> String? {
        guard turnPhase.isLive, let turn = pendingTurn else { return nil }
        let isItsConversation: Bool
        if !turn.convId.isEmpty {
            isItsConversation = turn.convId == id
        } else {
            let since = Int(turn.sentAt.timeIntervalSince1970) - 60
            isItsConversation = conversations.first(where: { $0.id == id })
                .map { $0.messageCount == 0 && $0.createdAt >= since } ?? false
        }
        return isItsConversation
            ? "A reply is still being written in this conversation. Stop it or wait for it to finish, then delete the conversation."
            : nil
    }

    func deleteConversation(_ id: String) {
        if let reason = deletionBlockedReason(for: id) {
            errorMessage = reason
            return
        }
        Task {
            do {
                try await api.deleteConversation(id: id)
                forgetTranscript(id)
                await loadConversations()
                await loadProjects()
                if id == currentConvId {
                    if let first = conversations.first {
                        selectConversation(first.id)
                    } else {
                        prepareForNewConversation()
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
        wakeGrace = false       // the engine is up: normal silence rules apply again
        turnReachedServer = true

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
            turnCompleted = true
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
            if pendingTurn?.convId.isEmpty == true { pendingTurn?.convId = convId }
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
            turnFailedOnServer = true
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

    /// The stream ended on its own (not Stop, not the watchdog, not navigation).
    /// What that means depends on how it ended:
    /// - `done` arrived: the turn is finished and saved.
    /// - the server reported a failure: nothing was saved, the alert says why.
    /// - neither: the connection went away under a turn the server is still
    ///   writing, so wait for the saved reply.
    private func finishStreaming(msgId: UUID) {
        flushPendingTokens()
        updateMessage(id: msgId) { $0.isStreaming = false }
        isStreaming = false
        isThinkingActive = false
        isFetching = false
        currentSearchQuery = nil
        currentToolLabel = nil
        agentStepLabel = nil
        streamingWaitMessage = nil
        wakeGrace = false
        staleConnectionTask?.cancel()
        staleConnectionTask = nil

        // If the turn ended without a server .title event, use the user's prompt
        // as a fallback title so the conversation is identifiable in the sidebar.
        // Not after a drop: the server is still on the turn and titles the
        // conversation itself when it ends, and a rename from here could land
        // after that and overwrite it.
        if turnCompleted || turnFailedOnServer,
           !receivedTitleDuringStream, !pendingFirstMessage.isEmpty, !currentConvId.isEmpty {
            let fallback = String(pendingFirstMessage.prefix(60))
            renameConversation(currentConvId, title: fallback)
        }
        pendingFirstMessage = ""
        receivedTitleDuringStream = false

        // Always refresh the conversation list — on success to pick up the server
        // title, on error/timeout so the sidebar reflects current server state.
        Task { await loadConversations() }

        let wasRetry = retryInFlight
        retryInFlight = false

        if turnCompleted {
            conversationHadSuccessfulSend = true
            pendingTurn = nil
            turnPhase = .idle
            // A retry told the server to delete from the last user row forward,
            // which is not necessarily the two messages resendLast() removed here
            // — a turn that ran tools saved more than two. And a turn sent while
            // an earlier one was unaccounted for, or over a copy that was never
            // refreshed, started from a transcript the server may not share.
            // Either way the one request it costs to ask the server is worth it.
            // Normal sends append on both sides and already agree.
            if wasRetry || reloadAfterTurn, !currentConvId.isEmpty {
                reloadAfterTurn = false
                Task { @MainActor [weak self] in
                    await self?.reloadHistoryFromServer()
                }
            } else {
                rememberTranscript()
            }
        } else if turnFailedOnServer {
            pendingTurn = nil
            turnPhase = .idle
        } else {
            beginAwaitingReply()
        }
    }

    // ── Waiting for a reply the stream did not deliver ────────────────────────

    /// After a stream ends without its reply the server does not stop: it
    /// finishes the turn and saves it. Poll for that, every 3 s, and put the
    /// saved reply on screen when it shows up.
    ///
    /// Ten minutes when the request is known to have arrived (a turn that loops
    /// through web searches runs three to four); ninety seconds when not one
    /// event came back, so it may never have. The whole time `turnPhase` says
    /// what is happening, and when the poll runs out it says that too, with a
    /// way to look again.
    ///
    /// It follows the turn, not the screen: if the user opens another
    /// conversation meanwhile the poll goes on, and the reply is saved for when
    /// they come back.
    private func beginAwaitingReply() {
        awaitTask?.cancel()
        guard let sentAt = pendingTurn?.sentAt else {
            turnPhase = .idle
            return
        }
        let reached = turnReachedServer
        turnPhase = .awaitingReply(since: Date(), reached: reached)
        awaitTask = Task { @MainActor [weak self] in
            let attempts = reached ? 200 : 30
            for attempt in 0..<attempts {
                if attempt > 0 { try? await Task.sleep(for: .seconds(3)) }
                guard let self, !Task.isCancelled,
                      let turn = self.pendingTurn, turn.sentAt == sentAt else { return }
                if let found = await self.finishedTurn(turn) {
                    guard !Task.isCancelled, self.pendingTurn?.sentAt == sentAt else { return }
                    self.applyRecoveredReply(convId: found.convId, history: found.history)
                    return
                }
            }
            guard let self, !Task.isCancelled, self.pendingTurn?.sentAt == sentAt else { return }
            if self.pendingTurnIsOnScreen {
                self.turnPhase = .unrecovered(reached: reached)
            } else {
                self.pendingTurn = nil
                self.turnPhase = .idle
            }
        }
    }

    /// The server's copy of the conversation `turn` was sent in, once it holds
    /// the finished turn. Nil while it does not, and while the server cannot be
    /// reached at all.
    private func finishedTurn(_ turn: PendingTurn) async -> (convId: String, history: [ConversationMessage])? {
        if !turn.convId.isEmpty {
            guard let history = try? await api.getMessages(conversationId: turn.convId),
                  Self.holdsFinishedTurn(history, text: turn.text, priorCopies: turn.priorCopies)
            else { return nil }
            return (turn.convId, history)
        }
        // A new conversation whose id never reached the app (it comes with the
        // title, at the end of the turn). The server created the row when the
        // turn started: find it among the conversations created since the send,
        // by the question it was created for.
        let since = Int(turn.sentAt.timeIntervalSince1970) - 60
        guard let list = try? await api.listConversations() else { return nil }
        let candidates = list.filter { $0.createdAt >= since && $0.messageCount >= 2 }
            .sorted { $0.createdAt > $1.createdAt }
        for candidate in candidates.prefix(5) {
            guard let history = try? await api.getMessages(conversationId: candidate.id),
                  Self.holdsFinishedTurn(history, text: turn.text, priorCopies: 0)
            else { continue }
            return (candidate.id, history)
        }
        return nil
    }

    /// True when `history` ends in an assistant reply and holds the question one
    /// more time than the transcript did before it was sent.
    ///
    /// "Ends in an assistant reply" alone is true of every conversation that
    /// already had a turn: the previous reply was taken for the new one, the
    /// reload dropped the pending question from the screen, and the poll stopped
    /// before the server had written a word.
    private static func holdsFinishedTurn(_ history: [ConversationMessage], text: String, priorCopies: Int) -> Bool {
        guard history.last?.role == "assistant" else { return false }
        return history.filter { $0.role == "user" && $0.content == text }.count > priorCopies
    }

    private func applyRecoveredReply(convId: String, history: [ConversationMessage]) {
        let onScreen = pendingTurnIsOnScreen && !isStreaming
            && (currentConvId.isEmpty || currentConvId == convId)
        pendingTurn = nil
        if onScreen {
            currentConvId = convId
            messages = merged(history)
            showLastThinking()
            conversationHadSuccessfulSend = true
            rememberTranscript()
            let now = Date()
            turnPhase = .restored(at: now)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.turnPhase == .restored(at: now) else { return }
                self.turnPhase = .idle
            }
        } else {
            // Another conversation is on screen. Save the reply so that opening
            // this one paints it at once.
            turnPhase = .idle
            remember(history.map {
                Message(role: $0.role == "user" ? .user : .assistant, content: $0.content,
                        thinkingContent: $0.thinkingContent)
            }, for: convId)
        }
        Task { await loadConversations() }
    }

    /// Replaces `messages` with the server's copy of the conversation.
    ///
    /// Used where the local array and the database can legitimately disagree:
    /// after a retry, and after a turn sent over a transcript that was not known
    /// to match. An empty response is ignored rather than applied — it means the
    /// fetch failed or raced a delete, and blanking the transcript over that is
    /// worse than showing something slightly stale.
    ///
    /// Image thumbnails and attached file names survive only on messages the
    /// server's copy leaves unchanged: the server stores neither.
    private func reloadHistoryFromServer() async {
        let id = currentConvId
        let transcript = transcriptID
        guard !id.isEmpty else { return }
        guard let history = try? await api.getMessages(conversationId: id),
              !history.isEmpty else { return }
        guard transcript == transcriptID, !isStreaming else { return }
        messages = merged(history)
        showLastThinking()
        rememberTranscript()
    }

    // ── Status line ───────────────────────────────────────────────────────────

    /// Silence, in seconds, after which the status line says no data is arriving.
    /// Heartbeats come every 5 s, so 8 s without one is already unusual; the
    /// watchdog gives up at `staleLimit`.
    private static let silenceWarning: TimeInterval = min(8, staleLimit / 2)

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// What the line above the input bar should say at `now`, or nil for
    /// nothing. The view calls this once a second, so the seconds in it count.
    func statusLine(now: Date) -> ChatStatusLine? {
        // A turn waited for in the background belongs to another conversation.
        let phase: TurnPhase = (pendingTurn == nil || pendingTurnIsOnScreen) ? turnPhase : .idle
        switch phase {
        case .streaming(let since):
            // False between `done` and the end of the stream (the title is
            // still to come): the reply is complete, there is nothing to report.
            guard isStreaming else { break }
            let time = Self.elapsed(from: since, to: now)
            if wakeGrace {
                return ChatStatusLine(text: "Waking the model… \(time)", tone: .progress, showsSpinner: true)
            }
            let silence = now.timeIntervalSince(lastEventDate)
            if silence >= Self.silenceWarning {
                return ChatStatusLine(
                    text: "No data from the server for \(Int(silence)) s. Checking the connection…",
                    tone: .warning, showsSpinner: true)
            }
            let label = streamingWaitMessage ?? "Receiving the reply…"
            return ChatStatusLine(text: "\(label) \(time)", tone: .progress, showsSpinner: true)

        case .awaitingReply(let since, let reached):
            let time = Self.elapsed(from: since, to: now)
            return ChatStatusLine(
                text: reached
                    ? "Connection lost. The server is still writing the reply; checking for it every 3 s (\(time))."
                    : "Connection lost before the server answered. Checking whether the message arrived (\(time)).",
                tone: .warning, showsSpinner: true, action: .stopWaiting)

        case .restored:
            return ChatStatusLine(text: "Reply restored from the server.", tone: .success)

        case .unrecovered(let reached):
            return ChatStatusLine(
                text: reached
                    ? "The reply has not shown up on the server. Check again, or resend the message."
                    : "The message does not seem to have reached the server. Check again, or resend it.",
                tone: .failure, action: .checkAgain)

        case .idle:
            break
        }

        switch transcriptLoad {
        case .refreshing(let since) where now.timeIntervalSince(since) >= 1:
            return ChatStatusLine(
                text: "Showing the saved copy. Refreshing… \(Self.elapsed(from: since, to: now))",
                tone: .progress, showsSpinner: true)
        case .stale(let reason):
            return ChatStatusLine(
                text: "Showing the saved copy. Could not refresh: \(reason)",
                tone: .warning, action: .retryLoad)
        default:
            return nil
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
