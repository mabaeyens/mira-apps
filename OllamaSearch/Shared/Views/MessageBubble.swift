import SwiftUI
import MarkdownUI    // from swift-markdown-ui

/// A single chat bubble — user (right, blue) or assistant (left, dark).
/// Markdown is rendered via swift-markdown-ui. Panels appear beneath the text.
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // ── Bubble content ────────────────────────────────────────
                Group {
                    if message.role == .user {
                        Text(message.content)
                            .textSelection(.enabled)
                    } else if message.isStreaming {
                        // Plain text during streaming — Markdown() re-parses on every
                        // token flush which causes visible stutter at 10 updates/second.
                        Text(message.content)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user
                              ? Color.blue
                              : Color(white: 0.15))
                )
                .foregroundStyle(Color.white)

                // ── Streaming cursor ──────────────────────────────────────
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 4)
                }

                // ── Sources panel ─────────────────────────────────────────
                if !message.fetchContext.isEmpty {
                    SourcesPanel(fetches: message.fetchContext)
                        .frame(maxWidth: 420, alignment: .leading)
                }

                // ── RAG panel ─────────────────────────────────────────────
                if !message.ragContext.isEmpty {
                    RAGPanel(chunks: message.ragContext)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
