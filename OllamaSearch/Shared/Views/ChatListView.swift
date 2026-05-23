#if os(iOS)
import SwiftUI

struct ChatListView: View {
    @Bindable var vm: ChatViewModel
    var onSelect: (String) -> Void
    var onMenu: () -> Void
    var onNewChat: () -> Void

    @State private var searchText = ""
    @State private var renamingConv: Conversation? = nil
    @State private var renameText = ""
    @State private var deletingConv: Conversation? = nil

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return vm.conversations }
        return vm.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(filteredConversations) { conv in
                    conversationRow(conv)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .background(Color.appBg.ignoresSafeArea())
        .alert("Rename conversation", isPresented: Binding(
            get: { renamingConv != nil },
            set: { if !$0 { renamingConv = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let conv = renamingConv {
                    vm.renameConversation(conv.id, title: renameText)
                }
                renamingConv = nil
            }
            Button("Cancel", role: .cancel) { renamingConv = nil }
        }
        .confirmationDialog(
            "Delete \"\(deletingConv?.title ?? "")\"?",
            isPresented: Binding(get: { deletingConv != nil }, set: { if !$0 { deletingConv = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let conv = deletingConv { vm.deleteConversation(conv.id) }
                deletingConv = nil
            }
            Button("Cancel", role: .cancel) { deletingConv = nil }
        } message: {
            let count = deletingConv?.messageCount ?? 0
            Text("This conversation has \(count) message\(count == 1 ? "" : "s") and cannot be recovered.")
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────

    private var header: some View {
        ZStack {
            Text("Chats")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            HStack {
                circleButton(icon: "line.3.horizontal", action: onMenu)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.appBg)
        .overlay(alignment: .bottom) {
            Color.borderSubtle.opacity(0.5).frame(height: 0.5)
        }
    }

    // ── Bottom bar (search + new chat pill) ───────────────────────────────────

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                TextField("Search", text: $searchText)
                    .font(Font.sidebarTitle)
                    .foregroundStyle(Color.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button(action: onNewChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New Chat")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Color.borderSubtle.opacity(0.5).frame(height: 0.5)
        }
    }

    // ── Conversation row ──────────────────────────────────────────────────────

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conv.title)
                    .font(Font.sidebarTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(relativeDate(conv.updatedAt))
                    .font(Font.sidebarSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceBg.opacity(0.45))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            vm.selectConversation(conv.id)
            onSelect(conv.id)
        }
        .contextMenu {
            Button {
                renameText = conv.title
                renamingConv = conv
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                requestDelete(conv)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                renameText = conv.title
                renamingConv = conv
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Color.appAccent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { requestDelete(conv) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func requestDelete(_ conv: Conversation) {
        if conv.messageCount > 0 {
            deletingConv = conv
        } else {
            vm.deleteConversation(conv.id)
        }
    }

    private func relativeDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func circleButton(icon: String, color: Color = Color.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .systemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
#endif
