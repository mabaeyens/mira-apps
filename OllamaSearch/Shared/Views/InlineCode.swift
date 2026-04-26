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

// MARK: - Flow layout key

private struct InlineIsCodeKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

// MARK: - Flow layout for mixed text + code chips

private struct InlineFlowLayout: Layout {
    private let vSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        compute(subviews: subviews, width: proposal.width ?? 300).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(subviews: subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Result {
        var frames: [CGRect]
        var size: CGSize
    }

    private func compute(subviews: Subviews, width cw: CGFloat) -> Result {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0

        for subview in subviews {
            let isCode = subview[InlineIsCodeKey.self]

            if isCode {
                let sz = subview.sizeThatFits(.unspecified)
                if x + sz.width > cw + 1 && x > 0 {
                    y += lineH + vSpacing; lineH = 0; x = 0
                }
                frames.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
                x += sz.width
                lineH = max(lineH, sz.height)
            } else {
                let ideal = subview.sizeThatFits(.unspecified)
                let rem = cw - x
                if ideal.width <= rem + 1 {
                    frames.append(CGRect(x: x, y: y, width: ideal.width, height: ideal.height))
                    x += ideal.width
                    lineH = max(lineH, ideal.height)
                } else {
                    if x > 0 { y += lineH + vSpacing; lineH = 0; x = 0 }
                    let wrapped = subview.sizeThatFits(ProposedViewSize(width: cw, height: nil))
                    frames.append(CGRect(x: 0, y: y, width: wrapped.width, height: wrapped.height))
                    y += wrapped.height + vSpacing; x = 0; lineH = 0
                }
            }
        }

        return Result(frames: frames, size: CGSize(width: cw, height: y + lineH))
    }
}

// MARK: - Inline paragraph renderer

struct InlineParagraphView: View {
    let raw: String

    private var segments: [InlineSegment] { parseInlineSegments(raw) }

    var body: some View {
        InlineFlowLayout {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let s):
                    Text(attrString(s))
                        .font(.chatBody)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutValue(key: InlineIsCodeKey.self, value: false)
                case .code(let c):
                    InlineCodeChip(code: c)
                        .layoutValue(key: InlineIsCodeKey.self, value: true)
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
