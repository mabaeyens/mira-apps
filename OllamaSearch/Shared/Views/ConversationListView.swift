import SwiftUI

/// Sidebar list of past conversations.
struct ConversationListView: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        List(selection: Binding<String?>(
            get: { vm.currentConvId.isEmpty ? nil : vm.currentConvId },
            set: { if let id = $0 { vm.selectConversation(id) } }
        )) {
            ForEach(vm.conversations) { conv in
                conversationRow(conv)
                    .tag(conv.id)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.sidebarBg)
        .safeAreaInset(edge: .top) {
            newChatButton
        }
    }

    // ── New Chat button ───────────────────────────────────────────────────────

    private var newChatButton: some View {
        Button(action: { vm.newConversation() }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.accent)
                Text("New Chat")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .font(.bookerly(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.sidebarBg)
    }

    // ── Conversation row ──────────────────────────────────────────────────────

    private func conversationRow(_ conv: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conv.title)
                .font(.bookerly(size: 14))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 4) {
                Text("\(conv.messageCount) msg")
                Text("·")
                Text(relativeDate(conv.updatedAt))
            }
            .font(.bookerly(size: 12))
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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

    // ── Date helper ───────────────────────────────────────────────────────────

    private func relativeDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
