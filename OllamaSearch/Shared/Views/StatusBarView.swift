import SwiftUI

/// Token counter badges — mirrors the web UI header badges.
/// Colour thresholds: ≤55% grey · 56–70% red bg · >70% dark bg (danger).
struct StatusBarView: View {
    let inputTokens: Int
    let outputTokens: Int
    let contextPct: Double

    var body: some View {
        HStack(spacing: 6) {
            badge("↑\(formatted(inputTokens)) ↓\(formatted(outputTokens))", color: .secondary)
            badge("ctx:\(Int(contextPct))%", color: ctxColor)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private var ctxColor: Color {
        if contextPct > 70 { return .red }
        if contextPct > 55 { return .orange }
        return .secondary
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(contextPct > 70 ? .white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(contextPct > 70 ? Color.red.opacity(0.8) :
                          contextPct > 55 ? Color.orange.opacity(0.15) :
                          Color.secondary.opacity(0.12))
            )
    }

    private func formatted(_ n: Int) -> String {
        n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
}

#Preview {
    HStack {
        StatusBarView(inputTokens: 12500, outputTokens: 3200, contextPct: 45)
        StatusBarView(inputTokens: 28000, outputTokens: 8100, contextPct: 62)
        StatusBarView(inputTokens: 48000, outputTokens: 12000, contextPct: 78)
    }
    .padding()
}
