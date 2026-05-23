import MarkdownUI
import SwiftUI

/// A single chat turn. User messages are right-aligned warm bubbles.
/// Assistant messages are full-width with no bubble — text sits directly on the
/// page background. During streaming a blinking DOS-style `_` cursor is shown.
struct MessageBubble: View {
    let message: Message
    var waitMessage: String? = nil
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
        .padding(.vertical, 8)
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
    //
    // MessageContentView splits content into prose (SelectableText / SwiftUI Text
    // with AttributedString) and fenced code blocks (CopyableCodeBlock).
    // macOS adds a right-click "Copy" context menu.

    @ViewBuilder
    private var assistantBubble: some View {
        assistantContent
            .contextMenu {
                if !message.isStreaming {
                    Button {
                        let content = message.content
                        #if os(macOS)
                        DispatchQueue.main.async {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                        }
                        #else
                        UIPasteboard.general.string = content
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.isStreaming {
                TimelineView(.periodic(from: .now, by: 0.53)) { tl in
                    let showCursor = Int(tl.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
                    let displayText = message.content.isEmpty ? (waitMessage ?? "") : message.content
                    Text("\(displayText)\(Text(showCursor ? "_" : " ").foregroundStyle(Color.accent))")
                        .font(.chatBody)
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                renderedMessageText
            }

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

    @ViewBuilder
    private var renderedMessageText: some View {
        Markdown(preprocessLatex(message.content))
            .markdownTheme(.app)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── Selectable prose renderer (iOS + macOS) ───────────────────────────────────
//
// SwiftUI Text with AttributedString(markdown:) correctly renders PresentationIntent
// attributes (list items, headings, etc.) that UITextView/NSTextView do not understand.
// .textSelection(.enabled) on the MessageContentView VStack creates a unified
// selection context across all Text views within a message.
private struct SelectableText: View {
    let content: String

    private var attributed: AttributedString {
        let processed = preprocessLatex(content)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        guard var attr = try? AttributedString(markdown: processed, options: options) else {
            return AttributedString(processed)
        }
        for run in attr.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                attr[run.range].font = .body.monospaced()
                #if os(iOS)
                attr[run.range].backgroundColor = Color(uiColor: .systemGray6)
                #else
                attr[run.range].backgroundColor = Color(nsColor: .windowBackgroundColor)
                #endif
            }
        }
        return attr
    }

    var body: some View {
        Text(attributed)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

// ── Mixed prose + code-block renderer ────────────────────────────────────────
//
// Splits the raw markdown into text segments and fenced code blocks.
// Prose is rendered by SelectableText (SwiftUI Text + AttributedString).
// Code blocks use CopyableCodeBlock (syntax highlight + copy button).
// .textSelection(.enabled) on the VStack creates a unified selection context
// across all Text views within a message.

struct MessageContentView: View {
    let content: String

    private var segments: [MessageSegment] { parseMessageSegments(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let prose):
                    let trimmed = prose.trimmingCharacters(in: .newlines)
                    if !trimmed.isEmpty {
                        SelectableText(content: trimmed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .codeBlock(let lang, let code):
                    CopyableCodeBlock(language: lang, content: code)
                case .table(let headers, let rows):
                    MarkdownTableBlock(headers: headers, rows: rows)
                }
            }
        }
    }
}
