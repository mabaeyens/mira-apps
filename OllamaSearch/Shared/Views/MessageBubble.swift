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
    //
    // iOS: MessageContentView splits the content into prose segments (SelectableText /
    //      UITextView) and code fence blocks (CopyableCodeBlock with syntax highlight).
    //      Long-press on prose gives real cursor + drag selection; code blocks have
    //      their own Copy button.
    // macOS: Text(AttributedString) with right-click "Copy" context menu.

    @ViewBuilder
    private var assistantBubble: some View {
        #if os(macOS)
        assistantContent
            .contextMenu {
                if !message.isStreaming {
                    Button {
                        let content = message.content
                        DispatchQueue.main.async {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        #else
        assistantContent
        #endif
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
        #if os(iOS)
        MessageContentView(content: message.content)
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        macOSMessageText
        #endif
    }

    #if os(macOS)
    private var macOSMessageText: some View {
        let segments = parseMessageSegments(preprocessLatex(message.content))
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let prose):
                    macOSProse(prose)
                case .codeBlock(let lang, let code):
                    CopyableCodeBlock(language: lang, content: code)
                case .table(let headers, let rows):
                    MarkdownTableBlock(headers: headers, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func macOSProse(_ prose: String) -> some View {
        let trimmed = prose.trimmingCharacters(in: .newlines)
        if !trimmed.isEmpty {
            SelectableTextMacOS(content: trimmed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif
}

// ── macOS NSTextView prose renderer ──────────────────────────────────────────
//
// Mirrors the iOS SelectableText approach but for macOS.
// NSTextView gives: native drag selection, paragraphSpacing between paragraphs,
// and NSTextTable rendering for markdown tables (which SwiftUI Text cannot show).

#if os(macOS)
// NSTextView subclass that derives its height from the actual allocated width.
// This breaks the circular sizing dependency: SwiftUI sets the frame width (via
// .frame(maxWidth: .infinity)), layout() fires, intrinsicContentSize re-measures
// at the real width, and SwiftUI adjusts the height. No sizeThatFits needed.
//
// lastLayoutWidth guard is critical — without it, invalidateIntrinsicContentSize()
// triggers another layout pass unconditionally, causing an infinite loop that
// manifests as the OnScrollGeometryChange fault.
private class AutosizingNSTextView: NSTextView {
    private var lastLayoutWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        let w = frame.width > 0 ? frame.width : 500
        container.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(manager.usedRect(for: container).height))
    }

    override func layout() {
        super.layout()
        guard abs(frame.width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = frame.width
        invalidateIntrinsicContentSize()
    }
}

private struct SelectableTextMacOS: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> AutosizingNSTextView {
        let tv = AutosizingNSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        return tv
    }

    func updateNSView(_ tv: AutosizingNSTextView, context: Context) {
        tv.textStorage?.setAttributedString(buildAttr())
        tv.invalidateIntrinsicContentSize()
    }

    // Split content into visual blocks, keeping consecutive list items together.
    // Adds \n\n between non-list lines so each becomes its own paragraph block.
    // Tables are already extracted by parseMessageSegments before we're called.
    private func paragraphBlocks(_ text: String) -> [String] {
        let lines = text.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            out.append(line)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("|") { continue }
            let nextT = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
            // Keep consecutive list items together — inserting \n\n would break the list
            if isListMarker(t) && isListMarker(nextT) { continue }
            out.append("")
        }
        // Collapse runs of blank lines, then split on \n\n
        var collapsed: [String] = []
        var prevBlank = false
        for line in out {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && prevBlank { continue }
            collapsed.append(line)
            prevBlank = blank
        }
        return collapsed.joined(separator: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isListMarker(_ t: String) -> Bool {
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        let digits = t.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let rest = t.dropFirst(digits.count)
            return rest.hasPrefix(". ") || rest.hasPrefix(") ")
        }
        return false
    }

    private func buildAttr() -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: 16)
        let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let fg = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0xFA/255, green: 0xFA/255, blue: 0xF9/255, alpha: 1)
                : NSColor(red: 0x1C/255, green: 0x19/255, blue: 0x17/255, alpha: 1)
        }
        let codeBg = NSColor.windowBackgroundColor.withAlphaComponent(0.5)

        // Parse each block independently so Apple's markdown parser can't misinterpret
        // special characters in one block (e.g. regex ^[...]) as spanning paragraph breaks.
        // Paragraph spacing is explicit — not delegated to NSAttributedString(.full).
        let blocks = paragraphBlocks(content)
        let combined = NSMutableAttributedString()

        for (i, block) in blocks.enumerated() {
            let blockAttr: NSMutableAttributedString
            if let ns = try? NSAttributedString(
                markdown: preprocessLatex(block),
                options: .init(interpretedSyntax: .full)
            ) {
                blockAttr = NSMutableAttributedString(attributedString: ns)
            } else {
                blockAttr = NSMutableAttributedString(string: block)
            }

            // Strip trailing newlines the markdown parser appends
            while blockAttr.length > 0 {
                let last = (blockAttr.string as NSString).character(at: blockAttr.length - 1)
                guard last == 0x000A || last == 0x2029 || last == 0x000D else { break }
                blockAttr.deleteCharacters(in: NSRange(location: blockAttr.length - 1, length: 1))
            }

            let range = NSRange(location: 0, length: blockAttr.length)
            blockAttr.enumerateAttribute(.font, in: range) { val, r, _ in
                if val == nil { blockAttr.addAttribute(.font, value: base, range: r) }
            }
            blockAttr.addAttribute(.foregroundColor, value: fg, range: range)
            blockAttr.enumerateAttribute(.font, in: range) { val, r, _ in
                if let f = val as? NSFont, f.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                    blockAttr.addAttribute(.font, value: mono, range: r)
                    blockAttr.addAttribute(.backgroundColor, value: codeBg, range: r)
                }
            }

            combined.append(blockAttr)

            if i < blocks.count - 1 {
                // Two \n creates an empty paragraph (blank line) between blocks.
                // paragraphSpacing on the trailing \n is ignored by NSLayoutManager,
                // which reads paragraph attributes from the first character of the paragraph.
                // Double newline is reliable and produces the same visual gap as Claude Desktop.
                combined.append(NSMutableAttributedString(string: "\n\n", attributes: [
                    .font: base, .foregroundColor: fg
                ]))
            }
        }

        return combined
    }
}
#endif

// ── iOS-only selectable text wrapper ─────────────────────────────────────────

#if os(iOS)
/// UITextView bridge that allows cursor placement and drag-handle selection.
/// SwiftUI Text with .textSelection only offers "Copy all" on iOS; this gives
/// the full selection UX matching native UIKit text views.
private struct SelectableText: UIViewRepresentable {
    let content: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0xFA/255, green: 0xFA/255, blue: 0xF9/255, alpha: 1)
                : UIColor(red: 0x1C/255, green: 0x19/255, blue: 0x17/255, alpha: 1)
        }
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
        let codeBg = UIColor.systemGray6
        let fg = uiView.textColor ?? UIColor.label

        let processed = preprocessLatex(content)
        guard let ns = try? NSAttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .full)
        ) else {
            uiView.font = body
            uiView.text = processed
            return
        }

        let mutable = NSMutableAttributedString(attributedString: ns)
        let fullRange = NSRange(location: 0, length: mutable.length)

        // Remap every font run to body size, preserving bold/italic traits.
        // Monospace runs (inline code + code block content) keep mono font and get
        // a subtle background so they're visually distinct.
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let f = value as? UIFont else {
                mutable.addAttribute(.font, value: body, range: range)
                return
            }
            let traits = f.fontDescriptor.symbolicTraits
            if traits.contains(.traitMonoSpace) {
                mutable.addAttribute(.font, value: mono, range: range)
                mutable.addAttribute(.backgroundColor, value: codeBg, range: range)
            } else {
                var keep: UIFontDescriptor.SymbolicTraits = []
                if traits.contains(.traitBold)   { keep.insert(.traitBold) }
                if traits.contains(.traitItalic) { keep.insert(.traitItalic) }
                let desc = body.fontDescriptor.withSymbolicTraits(keep) ?? body.fontDescriptor
                mutable.addAttribute(.font, value: UIFont(descriptor: desc, size: body.pointSize), range: range)
            }
        }

        mutable.addAttribute(.foregroundColor, value: fg, range: fullRange)
        uiView.attributedText = mutable

        // SwiftUI ScrollView wraps a UIScrollView that delays content touches by
        // default, which prevents UITextView's long-press selection gesture from
        // firing. Walk up once after layout to disable the delay.
        DispatchQueue.main.async {
            var v: UIView? = uiView.superview
            while let node = v {
                if let sv = node as? UIScrollView {
                    sv.delaysContentTouches = false
                    break
                }
                v = node.superview
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        return uiView.sizeThatFits(CGSize(width: width, height: .infinity))
    }
}

// ── Mixed prose + code-block renderer ────────────────────────────────────────
//
// Splits the raw markdown into text segments and fenced code blocks.
// Prose is rendered by SelectableText (UITextView → real selection).
// Code blocks use CopyableCodeBlock (syntax highlight + copy button).

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
#endif
