import SwiftUI

/// Scrollable list of chat bubbles with pin-to-bottom auto-scroll.
///
/// Scroll behaviour mirrors the web UI:
/// - Auto-scrolls to bottom as tokens arrive.
/// - User scrolling up unpins auto-scroll.
/// - Reaching within 80pt of bottom re-pins.
struct MessageListView: View {
    let messages: [Message]
    let isStreaming: Bool
    let currentSearchQuery: String?
    let isFetching: Bool

    @State private var scrollPinned = true
    private let bottomAnchor = "bottom"

    var body: some View {
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

                    // Invisible anchor for scroll-to-bottom
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
                // Re-pin button — appears when user has scrolled up
                if !scrollPinned && !messages.isEmpty {
                    Button {
                        scrollPinned = true
                        scrollToBottom(proxy: proxy)
                    } label: {
                        Label("Jump to bottom", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 8)
                }
            }
        }
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
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
