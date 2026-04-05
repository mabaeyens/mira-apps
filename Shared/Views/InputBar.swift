import SwiftUI

/// Compose bar at the bottom of the chat view.
/// - Send button swaps to a Stop (■) button while streaming.
/// - Attachment chips show staged files above the text field.
/// - The attachment picker button is platform-specific (injected via closure).
struct InputBar: View {
    @Binding var text: String
    let stagedNames: [String]
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onRemoveAttachment: (Int) -> Void
    let attachPicker: AnyView   // platform-specific picker injected from parent

    var body: some View {
        VStack(spacing: 4) {
            // ── Staged attachment chips ───────────────────────────────────
            if !stagedNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(stagedNames.enumerated()), id: \.offset) { idx, name in
                            attachmentChip(name: name, index: idx)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            // ── Input row ─────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 8) {
                attachPicker

                TextField("Message…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .onSubmit {
                        guard !isStreaming else { return }
                        onSend()
                    }
                    // Cmd+Enter sends on macOS
                    .keyboardShortcut(.return, modifiers: .command)

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.gray
                                        : Color.blue
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }

    private func attachmentChip(name: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.caption2)
            Text(name)
                .font(.caption)
                .lineLimit(1)
            Button {
                onRemoveAttachment(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.secondary.opacity(0.15))
        )
    }
}
