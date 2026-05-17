import SwiftUI

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let currentBackend: String
    let isSwitching: Bool
    let switchStatusMessage: String
    let liveModelName: String
    let liveContextWindow: Int
    let onSwitch: (String) async -> Void

    @State private var pendingBackend: String? = nil

    private struct ModelOption {
        let backend: String
        let displayName: String
        let subtitle: String
    }

    private let options: [ModelOption] = [
        .init(backend: "omlx",   displayName: "Qwen3.6-35B-A3B", subtitle: "oMLX · 262k context"),
        .init(backend: "ollama", displayName: "Qwen3.6-35B-A3B", subtitle: "Ollama · 262k context"),
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
                .disabled(isSwitching)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.borderSubtle)

            if isSwitching {
                switchingView
            } else if let pending = pendingBackend {
                confirmationView(for: pending)
            } else {
                modelListView
            }
        }
        .frame(width: 320)
        .background(Color.appBg)
        // Clear pending selection if the sheet is dismissed externally
        .onChange(of: isSwitching) { _, switching in
            if switching { pendingBackend = nil }
        }
    }

    // ── Progress view ─────────────────────────────────────────────────────────

    private var switchingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.yellow)
            Text(switchStatusMessage.isEmpty ? "Switching model…" : switchStatusMessage)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .animation(.default, value: switchStatusMessage)
            Text("Chat is paused during the switch.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    // ── Confirmation view ─────────────────────────────────────────────────────

    private func confirmationView(for backend: String) -> some View {
        let option = options.first { $0.backend == backend }
        let displayName = option?.displayName ?? backend
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Switch to \(displayName)?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text("The current model will stop and \(displayName) will start. Chat is paused for 30–60 seconds during the switch.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Cancel") {
                    pendingBackend = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.surfaceBg)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle, lineWidth: 1))
                )

                Button("Switch") {
                    let b = backend
                    pendingBackend = nil
                    Task { await onSwitch(b) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.appAccent))
            }
        }
        .padding(20)
    }

    // ── Model list ────────────────────────────────────────────────────────────

    private var modelListView: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.backend) { option in
                modelRow(option)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func modelRow(_ option: ModelOption) -> some View {
        let isActive = option.backend == currentBackend
        let displayName = isActive && !liveModelName.isEmpty ? liveModelName : option.displayName
        let backendLabel = option.backend == "omlx" ? "oMLX" : "Ollama"
        let subtitle: String = {
            if isActive && liveContextWindow > 0 {
                let ctxK = liveContextWindow / 1024
                return "\(backendLabel) · \(ctxK)k context"
            }
            return option.subtitle
        }()
        Button {
            guard !isActive else { return }
            pendingBackend = option.backend
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
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
    ModelPickerView(currentBackend: "ollama", isSwitching: false, switchStatusMessage: "", liveModelName: "Qwen3.6-35B-A3B", liveContextWindow: 262144, onSwitch: { _ in })
        .frame(height: 240)
}
