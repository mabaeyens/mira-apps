import SwiftUI

/// Sidebar list of past conversations.
/// Mirrors the web UI sidebar: title (ellipsis overflow) + relative timestamp + delete on hover.
struct ConversationListView: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        List(selection: Binding(
            get: { vm.currentConvId },
            set: { id in if let id { vm.selectConversation(id) } }
        )) {
            ForEach(vm.conversations) { conv in
                conversationRow(conv)
                    .tag(conv.id)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            Button(action: { vm.newConversation() }) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(relativeDate(conv.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Delete button (visible on hover via .swipeActions on iOS,
            // shown as ✕ button on macOS via contextMenu or hover)
        }
        .contextMenu {
            Button(role: .destructive) {
                vm.deleteConversation(conv.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.deleteConversation(conv.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Unix timestamp (Int) → human-readable relative string.
    private func relativeDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
