import SwiftUI

/// Scrollable list of chat bubbles with pin-to-bottom auto-scroll.
/// Shows a welcome screen when the conversation is empty.
struct MessageListView: View {
    let messages: [Message]
    let isStreaming: Bool
    let currentSearchQuery: String?
    let isFetching: Bool

    @State private var scrollPinned = true
    private let bottomAnchor = "bottom"

    var body: some View {
        if messages.isEmpty && !isStreaming {
            welcomeView
        } else {
            scrollingMessages
        }
    }

    // ── Welcome empty state ───────────────────────────────────────────────────

    private var welcomeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(Color.accent)
            Text("OllamaSearch")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text("How can I help?")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    // ── Message list ──────────────────────────────────────────────────────────

    private var scrollingMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                    }

                    // Activity indicators shown while streaming
                    if let query = currentSearchQuery {
                        activityRow(icon: "magnifyingglass", text: "Searching: \(query)")
                    }
                    if isFetching {
                        activityRow(icon: "arrow.down.circle", text: "Fetching page…")
                    }

                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: messages.last?.content) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in scrollPinned = false }
            )
            .overlay(alignment: .bottom) {
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
                    .padding(.bottom, 8)
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
