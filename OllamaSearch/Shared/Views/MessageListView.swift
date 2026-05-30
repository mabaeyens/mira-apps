import SwiftUI

/// Scrollable list of chat bubbles with pin-to-bottom auto-scroll.
/// Shows a welcome screen when the conversation is empty.
struct MessageListView: View {
    let messages: [Message]
    let isStreaming: Bool
    let currentSearchQuery: String?
    let isFetching: Bool
    var isLoadingMessages: Bool = false
    var failedUserMessageId: UUID? = nil
    var streamingWaitMessage: String? = nil
    var thinkingContent: String? = nil
    var isThinkingActive: Bool = false
    var currentToolLabel: String? = nil
    var agentStepLabel: String? = nil
    var topContentInset: CGFloat = 0
    var onResend: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onSendSuggestion: ((String) -> Void)? = nil

    @State private var scrollPinned = true
    @State private var thinkingExpanded = true
    private let bottomAnchor = "bottom"

    var body: some View {
        if isLoadingMessages {
            loadingView
        } else if messages.isEmpty && !isStreaming {
            welcomeView
        } else {
            scrollingMessages
        }
    }

    // ── Loading state ─────────────────────────────────────────────────────────

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.accent)
            Text("Loading conversation…")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    // ── Welcome empty state ───────────────────────────────────────────────────

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            MiraLogoView(size: 80)
            Spacer().frame(height: 20)
            Text("How can I help?")
                .font(.bookerly(size: 32, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Spacer().frame(height: 8)
            #if os(macOS)
            Text("Running locally on your Mac")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
            Spacer().frame(height: 36)
            HStack(spacing: 10) {
                ForEach(["What time is it?", "What's the weather in Madrid?", "Tell me a joke", "What's in the news today?"], id: \.self) { prompt in
                    Button(prompt) { onSendSuggestion?(prompt) }
                        .buttonStyle(SuggestionChipStyle())
                }
            }
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    // ── Message list ──────────────────────────────────────────────────────────

    private var scrollingMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topContentInset)
                    VStack(spacing: 0) {
                    ForEach(messages) { msg in
                        let isLastStreamingEmpty = msg.id == messages.last?.id
                            && msg.isStreaming && msg.content.isEmpty
                        MessageBubble(
                            message: msg,
                            waitMessage: isLastStreamingEmpty ? streamingWaitMessage : nil,
                            showResendActions: msg.id == failedUserMessageId,
                            onResend: onResend,
                            onEdit: onEdit
                        )
                    }

                    // Action buttons below last completed assistant message
                    if let lastMsg = messages.last,
                       lastMsg.role == .assistant,
                       !lastMsg.isStreaming,
                       !isStreaming {
                        #if os(macOS)
                        HStack(spacing: 0) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(lastMsg.content, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .frame(width: 32, height: 28)
                            }
                            .buttonStyle(.plain)
                            Button(action: { onResend?() }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .frame(width: 32, height: 28)
                            }
                            .buttonStyle(.plain)
                            Button(action: { onEdit?() }) {
                                Image(systemName: "pencil")
                                    .frame(width: 32, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #else
                        HStack(spacing: 24) {
                            Button(action: {
                                UIPasteboard.general.string = lastMsg.content
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            Button(action: { onResend?() }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            Button(action: { onEdit?() }) {
                                Image(systemName: "pencil")
                            }
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #endif
                    }

                    // Collapsible thinking block — open while streaming, collapses on first token
                    if let content = thinkingContent {
                        DisclosureGroup(isExpanded: $thinkingExpanded) {
                            ScrollView {
                                Text(content)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(maxHeight: 220)
                        } label: {
                            HStack(spacing: 6) {
                                if isThinkingActive {
                                    ProgressView().scaleEffect(0.65)
                                } else {
                                    Image(systemName: "brain")
                                        .font(.system(size: 11))
                                        .opacity(0.6)
                                }
                                Text(isThinkingActive ? "Thinking…" : "Thinking")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .onChange(of: isThinkingActive) { _, active in
                            if !active { thinkingExpanded = false }
                        }
                        .onChange(of: thinkingContent) { _, c in
                            if c != nil { thinkingExpanded = true }
                        }
                    }

                    // Activity indicators shown while streaming
                    if let query = currentSearchQuery {
                        activityRow(icon: "magnifyingglass", text: "Searching: \(query)")
                    }
                    if isFetching {
                        activityRow(icon: "arrow.down.circle", text: "Fetching page…")
                    }
                    if let label = currentToolLabel {
                        activityRow(icon: "gear", text: label)
                    }
                    if let label = agentStepLabel {
                        activityRow(icon: "arrow.triangle.2.circlepath", text: label)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.first?.id) {
                scrollPinned = true
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: messages.last?.content) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: thinkingContent) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            // When streaming starts (user just sent a message) always snap to bottom.
            .onChange(of: isStreaming) { _, nowStreaming in
                if nowStreaming {
                    scrollPinned = true
                    scrollToBottom(proxy: proxy)
                }
            }
            // Sole source of truth for pin/unpin — no DragGesture needed.
            // Hysteresis: pin at ≤80 pt from bottom, unpin at >120 pt.
            // This prevents the button from flickering at the threshold and,
            // crucially, stops the button from reappearing after it's tapped
            // (the button tap itself no longer sets scrollPinned = false).
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height
                    - geometry.contentInsets.bottom
            } action: { _, distance in
                if distance <= 80 {
                    scrollPinned = true
                } else if distance > 120 {
                    scrollPinned = false
                }
            }
            // safeAreaInset shrinks the scroll view's visible area so the button
            // never floats over message text — Apple-recommended pattern for
            // "scroll to bottom" affordances per HIG.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !scrollPinned && !messages.isEmpty {
                    Button {
                        scrollPinned = true
                        scrollToBottom(proxy: proxy)
                    } label: {
                        Label("Jump to bottom", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color.appBg.opacity(0.01)) // zero-opacity hit area
                }
            }
        }
        .background(Color.appBg)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private func activityRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
            Spacer()
            ProgressView().scaleEffect(0.7)
        }
        .font(.caption)
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}

#if os(macOS)
struct SuggestionChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .strokeBorder(Color.borderSubtle.opacity(configuration.isPressed ? 1.0 : 0.55), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
#endif
