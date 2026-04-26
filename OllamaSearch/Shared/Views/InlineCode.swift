import SwiftUI

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

// MARK: - Copy button for code blocks

struct CopyableCodeBlock: View {
    let language: String?
    let content: String
    let label: AnyView
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

            label
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
