import SwiftUI
import Highlightr

// MARK: - Message segment model (code fences vs prose)

enum MessageSegment {
    case text(String)
    case codeBlock(language: String?, content: String)
    case table(headers: [String], rows: [[String]])
}

func parseMessageSegments(_ raw: String) -> [MessageSegment] {
    guard let regex = try? NSRegularExpression(
        pattern: #"```([^\n]*)\n([\s\S]*?)```"#
    ) else { return splitTables(raw) }

    let ns = raw as NSString
    var segments: [MessageSegment] = []
    var lastEnd = 0

    for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
        let before = NSRange(location: lastEnd, length: match.range.location - lastEnd)
        if before.length > 0 {
            segments.append(contentsOf: splitTables(ns.substring(with: before)))
        }
        let langStr = match.range(at: 1).location != NSNotFound
            ? ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            : ""
        let codeStr = match.range(at: 2).location != NSNotFound
            ? ns.substring(with: match.range(at: 2))
            : ""
        segments.append(.codeBlock(language: langStr.isEmpty ? nil : langStr, content: codeStr))
        lastEnd = match.range.location + match.range.length
    }
    if lastEnd < ns.length {
        segments.append(contentsOf: splitTables(ns.substring(from: lastEnd)))
    }
    return segments.isEmpty ? [.text(raw)] : segments
}

// Scans a prose string for GFM table blocks and splits them into .table segments.
// Apple's NSAttributedString markdown parser does not support GFM tables — it
// discards the pipe structure and flows cell content as inline runs. We must
// detect and extract tables before any markdown parsing occurs.
private func splitTables(_ text: String) -> [MessageSegment] {
    let lines = text.components(separatedBy: "\n")
    var result: [MessageSegment] = []
    var buffer: [String] = []
    var i = 0

    while i < lines.count {
        if i + 1 < lines.count,
           isTableRow(lines[i]),
           isTableSeparator(lines[i + 1]) {
            let prose = buffer.joined(separator: "\n")
            if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(prose))
            }
            buffer = []

            let headers = tableRowCells(lines[i])
            i += 2
            var rows: [[String]] = []
            while i < lines.count && isTableRow(lines[i]) {
                rows.append(tableRowCells(lines[i]))
                i += 1
            }
            if !headers.isEmpty {
                result.append(.table(headers: headers, rows: rows))
            }
        } else {
            buffer.append(lines[i])
            i += 1
        }
    }

    let remaining = buffer.joined(separator: "\n")
    if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(.text(remaining))
    }
    return result.isEmpty ? [.text(text)] : result
}

private func isTableRow(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).contains("|")
}

private func isTableSeparator(_ line: String) -> Bool {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.contains("|"), t.contains("-") else { return false }
    let stripped = t
        .replacingOccurrences(of: "|", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: " ", with: "")
    return stripped.isEmpty
}

private func tableRowCells(_ line: String) -> [String] {
    var cells = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
    if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
    if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: - LaTeX symbol → Unicode preprocessing

func preprocessLatex(_ text: String) -> String {
    let replacements: [(String, String)] = [
        ("$\\rightarrow$", "→"), ("$\\leftarrow$", "←"),
        ("$\\Rightarrow$", "⇒"), ("$\\Leftarrow$", "⇐"),
        ("$\\leftrightarrow$", "↔"), ("$\\Leftrightarrow$", "⇔"),
        ("$\\uparrow$", "↑"), ("$\\downarrow$", "↓"),
        ("$\\leq$", "≤"), ("$\\geq$", "≥"), ("$\\neq$", "≠"),
        ("$\\approx$", "≈"), ("$\\equiv$", "≡"), ("$\\propto$", "∝"),
        ("$\\pm$", "±"), ("$\\times$", "×"), ("$\\div$", "÷"),
        ("$\\cdot$", "·"), ("$\\infty$", "∞"),
        ("$\\sum$", "∑"), ("$\\prod$", "∏"), ("$\\int$", "∫"),
        ("$\\partial$", "∂"), ("$\\nabla$", "∇"), ("$\\sqrt{}$", "√"),
        ("$\\in$", "∈"), ("$\\notin$", "∉"), ("$\\subset$", "⊂"),
        ("$\\supset$", "⊃"), ("$\\cup$", "∪"), ("$\\cap$", "∩"),
        ("$\\forall$", "∀"), ("$\\exists$", "∃"), ("$\\neg$", "¬"),
        ("$\\alpha$", "α"), ("$\\beta$", "β"), ("$\\gamma$", "γ"),
        ("$\\delta$", "δ"), ("$\\epsilon$", "ε"), ("$\\eta$", "η"),
        ("$\\theta$", "θ"), ("$\\lambda$", "λ"), ("$\\mu$", "μ"),
        ("$\\nu$", "ν"), ("$\\xi$", "ξ"), ("$\\pi$", "π"),
        ("$\\rho$", "ρ"), ("$\\sigma$", "σ"), ("$\\tau$", "τ"),
        ("$\\phi$", "φ"), ("$\\chi$", "χ"), ("$\\psi$", "ψ"),
        ("$\\omega$", "ω"), ("$\\Gamma$", "Γ"), ("$\\Delta$", "Δ"),
        ("$\\Theta$", "Θ"), ("$\\Lambda$", "Λ"), ("$\\Pi$", "Π"),
        ("$\\Sigma$", "Σ"), ("$\\Phi$", "Φ"), ("$\\Psi$", "Ψ"),
        ("$\\Omega$", "Ω"),
    ]
    var result = text
    for (latex, unicode) in replacements {
        result = result.replacingOccurrences(of: latex, with: unicode)
    }
    return result
}

// MARK: - Inline segment model

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
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if let attr = highlighted {
                    Text(attr)
                        .textSelection(.enabled)
                } else {
                    Text(code)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, alignment: .leading)
        }
        .task(id: colorScheme) { highlighted = computeHighlighted() }
    }

    private func computeHighlighted() -> AttributedString? {
        guard let lang = language.flatMap({ Self.languageMap[$0.lowercased()] }) else { return nil }
        let h = Highlightr()
        h?.setTheme(to: colorScheme == .dark ? "atom-one-dark" : "atom-one-light")
        #if os(macOS)
        h?.theme.setCodeFont(NSFont(name: "Menlo", size: 16)
            ?? NSFont.monospacedSystemFont(ofSize: 16, weight: .regular))
        #else
        h?.theme.setCodeFont(UIFont(name: "Menlo", size: 16)
            ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular))
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

// MARK: - Markdown table renderer

struct MarkdownTableBlock: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(cells: headers, isHeader: true)
                divider(opacity: 0.2)
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    tableRow(cells: padded(row), isHeader: false)
                        .background(r % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                    divider(opacity: 0.08)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tableRow(cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(attrCell(cell))
                    .font(isHeader ? .system(size: 13, weight: .semibold) : .system(size: 13))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 80, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .textSelection(.enabled)
                if i < cells.count - 1 {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                }
            }
        }
        .background(isHeader ? Color.primary.opacity(0.07) : Color.clear)
    }

    private func divider(opacity: Double) -> some View {
        Rectangle().fill(Color.primary.opacity(opacity)).frame(height: 1)
    }

    private func padded(_ row: [String]) -> [String] {
        var r = row
        while r.count < headers.count { r.append("") }
        return Array(r.prefix(headers.count))
    }

    private func attrCell(_ cell: String) -> AttributedString {
        (try? AttributedString(
            markdown: cell,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cell)
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
