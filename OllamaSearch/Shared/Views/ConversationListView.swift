import SwiftUI

/// Sidebar list of past conversations.
struct ConversationListView: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        Group {
            if vm.isLoadingConversations && vm.conversations.isEmpty {
                loadingView
            } else if vm.conversations.isEmpty {
                emptyView
            } else {
                conversationList
            }
        }
        .background(Color.sidebarBg)
        .navigationTitle("Mira")
        #if os(macOS)
        .safeAreaInset(edge: .top) {
            newChatButton
        }
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.accent)
                }
            }
        }
        #endif
    }

    // ── Loading / empty states ────────────────────────────────────────────────

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting…")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text("No conversations")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Button("Retry") {
                Task { await vm.loadConversations() }
            }
            .buttonStyle(.bordered)
            .tint(Color.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationList: some View {
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
        .refreshable { await vm.loadConversations() }
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
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.sidebarBg)
    }

    // ── Conversation row ──────────────────────────────────────────────────────

    private func conversationRow(_ conv: Conversation) -> some View {
        let isLoading = vm.loadingConvId == conv.id
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(conv.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text("\(conv.messageCount) msg")
                    Text("·")
                    Text(relativeDate(conv.updatedAt))
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
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
