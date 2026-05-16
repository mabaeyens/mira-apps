import SwiftUI
import MarkdownUI

/// A single chat turn. User messages are right-aligned warm bubbles.
/// Assistant messages are full-width with no bubble — text sits directly on the
/// page background. During streaming a blinking DOS-style `_` cursor is shown.
struct MessageBubble: View {
    let message: Message
    var showResendActions: Bool = false
    var onResend: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:      userBubble
        case .assistant: assistantBubble
        case .info:      infoBanner
        }
    }

    // ── Info banner (model switch, etc.) ──────────────────────────────────────

    private var infoBanner: some View {
        Text(message.content)
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
    }

    // ── User bubble ───────────────────────────────────────────────────────────

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: 6) {
                if !message.imageAttachments.isEmpty {
                    thumbnailRow
                }
                if !message.content.isEmpty {
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
                if showResendActions {
                    resendActions
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private var resendActions: some View {
        HStack(spacing: 10) {
            Button(action: { onEdit?() }) {
                Label("Edit", systemImage: "pencil")
                    .font(.caption)
            }
            Button(action: { onResend?() }) {
                Label("Resend", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.textSecondary)
    }

    private var thumbnailRow: some View {
        HStack(spacing: 6) {
            ForEach(message.imageAttachments.indices, id: \.self) { i in
                thumbnailImage(message.imageAttachments[i])
            }
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ data: Data) -> some View {
        #if os(iOS)
        if let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #elseif os(macOS)
        if let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #endif
    }

    // ── Assistant bubble ──────────────────────────────────────────────────────

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Content — plain Text while streaming (fast, no re-parse),
            // full Markdown once done.
            if message.isStreaming {
                TimelineView(.periodic(from: .now, by: 0.53)) { tl in
                    let showCursor = Int(tl.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
                    Text("\(message.content)\(Text(showCursor ? "_" : " ").foregroundStyle(Color.accent))")
                        .font(.chatBody)
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Markdown(message.content)
                    .markdownTheme(.app)
                    .markdownBlockStyle(\.paragraph) { cfg in
                        let raw = cfg.content.renderMarkdown()
                        if raw.contains("`") {
                            InlineParagraphView(raw: raw)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            cfg.label
                        }
                    }
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
    }
}
