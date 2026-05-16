import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var serverInfo: ServerInfo? = nil
    @State private var loadingInfo = true

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MiraLogoView(size: 120, playIntro: true)
                    .padding(.top, 40)

                Spacer().frame(height: 20)

                Text("Mira")
                    .font(.bookerly(size: 28, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 28)

                Text(
                    "The name Mira is the Spanish imperative of mirar (\u{201C}look!\u{201D}), " +
                    "the Latin word for \u{201C}wonder\u{201D} and the name of one of the oldest variable double stars " +
                    "observed by astronomers, a red giant whose brightness pulses on a 332-day cycle.\n\n" +
                    "With Mira, inference runs entirely on your Mac, this app is simply a window into it, " +
                    "so your conversations stay private and never touch an external server.\n\n" +
                    "Mira captures the spirit of the project: a quiet, local intelligence " +
                    "that looks with you, always on your side."
                )
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)

                Spacer().frame(height: 28)

                // ── System info ───────────────────────────────────────────────
                VStack(spacing: 0) {
                    if loadingInfo {
                        ProgressView()
                            .frame(height: 80)
                    } else {
                        systemInfoGrid(rows: [
                            ("Model",    serverInfo?.model    ?? "—"),
                            ("Backend",  serverInfo?.backendDisplayName ?? "—"),
                            ("Server",   serverInfo?.host     ?? "—"),
                            ("Context",  serverInfo?.contextWindowFormatted ?? "—"),
                            ("Hardware", serverInfo?.hardware ?? "—"),
                        ])
                    }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1)
                        )
                )

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .background(Color.appBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                serverInfo = try await APIClient.shared.fetchServerInfo()
            } catch {
                serverInfo = nil
            }
            loadingInfo = false
        }
    }

    @ViewBuilder
    private func systemInfoGrid(rows: [(String, String)]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .top) {
                    Text(label)
                        .font(.bookerly(size: 13, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Text(value)
                        .font(.bookerly(size: 13, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview {
    AboutView()
        .frame(width: 480, height: 600)
}
