import SwiftUI
import MarkdownUI

/// A single chat turn. User messages are right-aligned warm bubbles.
/// Assistant messages are full-width with no bubble — text sits directly on the
/// page background. During streaming a blinking DOS-style `_` cursor is shown.
struct MessageBubble: View {
    let message: Message
    @State private var cursorOn = true

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    // ── User bubble ───────────────────────────────────────────────────────────

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 72)
            Text(message.content)
                .font(.chatBody)
                .textSelection(.enabled)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.userBubbleBg)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // ── Assistant bubble ──────────────────────────────────────────────────────

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Content — plain Text while streaming (fast, no re-parse),
            // full Markdown once done.
            if message.isStreaming {
                Text("\(message.content)\(Text(cursorOn ? "_" : " ").foregroundStyle(Color.accent))")
                    .font(.chatBody)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Markdown(message.content)
                    .markdownTheme(.app)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sources and RAG panels (appear below the answer)
            if !message.fetchContext.isEmpty {
                SourcesPanel(fetches: message.fetchContext)
            }
            if !message.ragContext.isEmpty {
                RAGPanel(chunks: message.ragContext)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        // Cursor blink: task re-fires whenever isStreaming toggles.
        // When streaming ends the task is cancelled, cursorOn is reset to false.
        .task(id: message.isStreaming) {
            guard message.isStreaming else { cursorOn = false; return }
            cursorOn = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                guard !Task.isCancelled else { break }
                cursorOn.toggle()
            }
            cursorOn = false
        }
    }
}
