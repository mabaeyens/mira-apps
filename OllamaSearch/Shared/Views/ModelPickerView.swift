import SwiftUI

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let currentBackend: String
    let isSwitching: Bool
    let onSwitch: (String) async -> Void

    private struct ModelOption {
        let backend: String
        let displayName: String
        let subtitle: String
    }

    private let options: [ModelOption] = [
        .init(backend: "omlx",   displayName: "Qwen3.6-35B-A3B", subtitle: "oMLX · 262k context"),
        .init(backend: "ollama", displayName: "Gemma4:26b",       subtitle: "Ollama · 65k context"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Switch Model")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.borderSubtle)

            if isSwitching {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Color.appAccent)
                    Text("Switching model…")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Stopping old server and starting the new one.\nThis takes about 30–60 seconds.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 10) {
                    ForEach(options, id: \.backend) { option in
                        modelRow(option)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .background(Color.appBg)
    }

    @ViewBuilder
    private func modelRow(_ option: ModelOption) -> some View {
        let isActive = option.backend == currentBackend
        Button {
            guard !isActive else { return }
            Task { await onSwitch(option.backend) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.appAccent.opacity(0.08) : Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isActive ? Color.appAccent.opacity(0.35) : Color.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isActive || isSwitching)
    }
}

#Preview {
    ModelPickerView(currentBackend: "ollama", isSwitching: false, onSwitch: { _ in })
        .frame(height: 220)
}
