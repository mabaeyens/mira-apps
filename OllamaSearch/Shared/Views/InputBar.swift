import SwiftUI

/// Compose bar at the bottom of the chat view.
/// - Send button swaps to a Stop (■) button while streaming.
/// - Attachment chips show staged files above the text field.
/// - The attachment picker button is platform-specific (injected via closure).
struct InputBar: View {
    @Binding var text: String
    @Binding var thinkingEnabled: Bool
    let stagedNames: [String]
    let isStreaming: Bool
    let modelStatusColor: Color
    let modelName: String
    let currentBackend: String
    let isSwitchingBackend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onRemoveAttachment: (Int) -> Void
    let onShowModelPicker: () -> Void
    let attachPicker: AnyView

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // ── Staged attachment chips ───────────────────────────────────
            if !stagedNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(stagedNames.enumerated()), id: \.offset) { idx, name in
                            attachmentChip(name: name, index: idx)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // ── Input row inside a rounded bordered container ─────────────
            HStack(alignment: .center, spacing: 10) {
                attachPicker

                Button {
                    thinkingEnabled.toggle()
                } label: {
                    Image(systemName: thinkingEnabled ? "brain.fill" : "brain")
                        .foregroundStyle(thinkingEnabled ? Color.accent : Color.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                // ── Model switcher ──────────────────────────────────────
                Button {
                    onShowModelPicker()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(modelStatusColor)
                            .frame(width: 6, height: 6)
                        Text(modelName.isEmpty
                            ? (currentBackend == "omlx" ? "oMLX" : "Ollama")
                            : modelName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textSecondary)
                            .opacity(0.7)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.surfaceBg)
                            .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSwitchingBackend)
                #if os(macOS)
                .focusEffectDisabled()
                #endif

                TextField("Message…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.chatBody)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.vertical, 2)
                    .focused($isFocused)
                    .onSubmit {
                        guard !isStreaming else { return }
                        isFocused = false
                        onSend()
                    }
                    .keyboardShortcut(.return, modifiers: .command)

                actionButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.borderSubtle.opacity(0.6), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(Color.appBg)
    }

    // ── Send / Stop button ────────────────────────────────────────────────────

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        } else {
            let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                isFocused = false
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(canSend ? Color.accent : Color.borderSubtle))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    // ── Attachment chip ───────────────────────────────────────────────────────

    private func attachmentChip(name: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.caption2)
                .foregroundStyle(Color.accent)
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Color.textPrimary)
            Button {
                onRemoveAttachment(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.surfaceBg)
                .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
        )
    }
}
