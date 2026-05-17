import SwiftUI
import Highlightr

// MARK: - Segment model

private enum InlineSegment {
    case text(String)
    case code(String)
}

private func parseInlineSegments(_ raw: String) -> [InlineSegment] {
    guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else {
        return [.text(raw)]
    }
    let ns = raw as NSString
    var result: [InlineSegment] = []
    var lastEnd = 0
    for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
        let before = match.range.location - lastEnd
        if before > 0 {
            result.append(.text(ns.substring(with: NSRange(location: lastEnd, length: before))))
        }
        result.append(.code(ns.substring(with: match.range(at: 1))))
        lastEnd = match.range.location + match.range.length
    }
    if lastEnd < ns.length {
        result.append(.text(ns.substring(from: lastEnd)))
    }
    return result.isEmpty ? [.text(raw)] : result
}

// MARK: - Inline code chip

struct InlineCodeChip: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button(action: doCopy) {
            HStack(spacing: 3) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(copied ? Color.accent.opacity(0.12) : Color.userBubbleBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(copied ? Color.accent : Color.borderSubtle, lineWidth: 1)
                    )
            )
            .foregroundStyle(copied ? Color.accent : Color.textPrimary)
            .animation(.spring(duration: 0.2), value: copied)
        }
        .buttonStyle(.plain)
    }

    private func doCopy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

// MARK: - Syntax-highlighted code view

struct HighlightedCodeView: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString? = nil

    // Aliases mapped to their Highlight.js canonical name.
    private static let languageMap: [String: String] = [
        "py": "python", "python": "python",
        "html": "html", "xml": "xml",
        "powershell": "powershell", "ps1": "powershell",
        "bash": "bash", "sh": "bash", "zsh": "bash",
        "swift": "swift",
        "js": "javascript", "javascript": "javascript",
        "ts": "typescript", "typescript": "typescript",
        "yaml": "yaml", "yml": "yaml",
        "json": "json",
        "sql": "sql",
        "md": "markdown", "markdown": "markdown",
    ]

    var body: some View {
        Group {
            if let attr = highlighted {
                Text(attr)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .task(id: colorScheme) { highlighted = computeHighlighted() }
    }

    private func computeHighlighted() -> AttributedString? {
        guard let lang = language.flatMap({ Self.languageMap[$0.lowercased()] }) else { return nil }
        let h = Highlightr()
        h?.setTheme(to: colorScheme == .dark ? "atom-one-dark" : "atom-one-light")
        #if os(macOS)
        h?.theme.setCodeFont(NSFont(name: "Menlo", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #else
        h?.theme.setCodeFont(UIFont(name: "Menlo", size: 13)
            ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #endif
        guard let ns = h?.highlight(code, as: lang) else { return nil }
        let mutable = NSMutableAttributedString(attributedString: ns)
        mutable.removeAttribute(.backgroundColor,
                                range: NSRange(location: 0, length: mutable.length))
        #if os(macOS)
        return try? AttributedString(mutable, including: \.appKit)
        #else
        return try? AttributedString(mutable, including: \.uiKit)
        #endif
    }
}

// MARK: - Copy button for code blocks

struct CopyableCodeBlock: View {
    let language: String?
    let content: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                Button(action: doCopy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "square.on.square")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(copied ? Color.accent.opacity(0.15) : Color.borderSubtle.opacity(0.5))
                    )
                    .foregroundStyle(copied ? Color.accent : Color.textSecondary)
                    .animation(.spring(duration: 0.2), value: copied)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)
                .opacity(0.5)

            HighlightedCodeView(code: content, language: language)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surfaceBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.vertical, 4)
    }

    private func doCopy() {
        #if os(iOS)
        UIPasteboard.general.string = content
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

// MARK: - Inline paragraph renderer
//
// Each inline code segment breaks onto its own line so copy-pasteable
// snippets are visually distinct. The flow layout is intentionally removed:
// sentences like "Run `pip install X`" read better with the command below
// the prose than squeezed inline.

struct InlineParagraphView: View {
    let raw: String

    private var segments: [InlineSegment] { parseInlineSegments(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Text(attrString(s))
                            .font(.chatBody)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                case .code(let c):
                    InlineCodeChip(code: c)
                }
            }
        }
    }

    private func attrString(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }
}
