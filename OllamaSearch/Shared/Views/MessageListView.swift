import SwiftUI

/// Scrollable list of chat bubbles with pin-to-bottom auto-scroll.
/// Shows a welcome screen when the conversation is empty.
struct MessageListView: View {
    let messages: [Message]
    let isStreaming: Bool
    let currentSearchQuery: String?
    let isFetching: Bool
    var isLoadingMessages: Bool = false

    @State private var scrollPinned = true
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
            MiraLogoView(size: 88)
            Spacer().frame(height: 22)
            Text("Mira")
                .font(.bookerly(size: 28, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer().frame(height: 8)
            Text("How can I help?")
                .font(.bookerly(size: 20))
                .foregroundStyle(Color.textSecondary)
            Spacer()
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
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messages.count) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: messages.last?.content) {
                if scrollPinned { scrollToBottom(proxy: proxy) }
            }
            // When streaming starts (user just sent a message) always snap to bottom.
            .onChange(of: isStreaming) { _, nowStreaming in
                if nowStreaming {
                    scrollPinned = true
                    scrollToBottom(proxy: proxy)
                }
            }
            // Unpin on any upward drag so the button appears immediately.
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in scrollPinned = false }
            )
            // Re-pin (and hide the button) once the user scrolls back near the
            // bottom. The 80 pt threshold makes it disappear before the very end
            // so the transition feels instant rather than lagging behind the finger.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height
                    - geometry.contentInsets.bottom
                return distanceFromBottom <= 80
            } action: { _, isAtBottom in
                if isAtBottom { scrollPinned = true }
            }
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
