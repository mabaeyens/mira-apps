import SwiftUI

// ── Sidebar ───────────────────────────────────────────────────────────────────

struct ConversationListView: View {
    @Environment(ChatViewModel.self) private var vm
    var onTap: ((String) -> Void)? = nil
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    var onSettings: (() -> Void)? = nil
    var isReachable: Bool = true
    var connectionIcon: String = "wifi"
    var onChats: (() -> Void)? = nil
    var onNewChat: (() -> Void)? = nil
    #endif

    @State private var renamingConv: Conversation? = nil
    @State private var renameText: String = ""
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var showAddProject = false
    @State private var showMemories = false
    @State private var isRefreshing = false
    @State private var deletingConv: Conversation? = nil
    @Environment(CloudPreferences.self) private var prefs

    private var filteredConversations: [Conversation] {
        guard !debouncedSearch.isEmpty else { return vm.conversations }
        return vm.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(debouncedSearch)
        }
    }

    var body: some View {
        Group {
            if vm.isLoadingConversations && vm.conversations.isEmpty {
                loadingView
            } else if vm.conversations.isEmpty && vm.projects.isEmpty {
                emptyView
            } else {
                sidebarList
            }
        }
        #if os(macOS)
        // Subtle warm tint, distinct from the chat area's appBg, so the sidebar
        // reads as its own surface (Notes / Claude-style separation). New Chat and
        // Memories live in the window toolbar now, so the list runs to the bottom.
        .background(Color.sidebarBg)
        #else
        .background(Color.appBg)
        .safeAreaInset(edge: .top) {
            iosHeader
        }
        .safeAreaInset(edge: .bottom) {
            iosNewChatPill
        }
        #endif
        .sheet(isPresented: $showAddProject) {
            AddProjectSheet(isPresented: $showAddProject)
        }
        .sheet(isPresented: $showMemories) {
            MemoriesView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let date = vm.offlineCacheDate {
                offlineCacheBanner(date)
            }
        }
    }

    private func offlineCacheBanner(_ date: Date) -> some View {
        let formatted = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        return HStack(spacing: 6) {
            Image(systemName: "icloud.slash")
                .font(Font.sidebarMeta)
            Text("Offline · cached \(formatted)")
                .font(Font.sidebarMeta)
        }
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Color.borderSubtle.frame(height: 0.5) }
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
            .tint(Color.appAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Main list ─────────────────────────────────────────────────────────────

    private var sidebarList: some View {
        List {
            #if os(iOS)
            if onChats != nil {
                Section {
                    Button(action: { onChats?() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 20)
                            Text("Chats")
                                .font(Font.sidebarTitle.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.iconSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
            }
            #endif

            // Projects section — collapsible
            if !vm.projects.isEmpty {
                Section {
                    if prefs.projectsExpanded {
                        ForEach(vm.projects) { project in
                            projectRow(project)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        addProjectButton
                    }
                } header: {
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            prefs.projectsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            sectionHeader("Projects")
                            Image(systemName: prefs.projectsExpanded ? "chevron.down" : "chevron.right")
                                .font(.iconSmall)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Conversations section
            Section {
                #if os(iOS)
                let displayConvs = filteredConversations
                let titleOnly = onChats != nil
                #else
                let displayConvs = filteredConversations
                let titleOnly = false
                #endif
                ForEach(displayConvs) { conv in
                    conversationRow(conv, isSelected: conv.id == vm.currentConvId, titleOnly: titleOnly)
                        .tag(conv.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
                if vm.projects.isEmpty {
                    addProjectButton
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                #if os(iOS)
                if onChats != nil {
                    sectionHeader("Recent")
                } else {
                    sectionHeader("Conversations")
                }
                #else
                sectionHeader("Conversations")
                #endif
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        #if os(macOS)
        // Drop the List's automatic titlebar inset so it doesn't stack with the card's
        // own top margin, then add a small fixed breathing space above the first header.
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 14) }
        .searchable(text: $searchText, prompt: "Search conversations")
        #endif
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            debouncedSearch = searchText
        }
        .refreshable { await vm.loadConversations() }
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
        .alert(
            "Delete \"\(deletingConv?.title ?? "")\"?",
            isPresented: Binding(get: { deletingConv != nil }, set: { if !$0 { deletingConv = nil } })
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

    private func requestDelete(_ conv: Conversation) {
        if conv.messageCount > 0 {
            deletingConv = conv
        } else {
            vm.deleteConversation(conv.id)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .miraSecondaryCaption()
    }

    // ── Project rows ──────────────────────────────────────────────────────────

    private func projectRow(_ project: Project) -> some View {
        Button {
            vm.newConversation(projectId: project.id)
            #if !os(macOS)
            onNewChat?()
            #endif
        } label: {
            HStack(spacing: 10) {
                Image(systemName: project.icon)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(Font.sidebarTitle.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if let sub = project.subtitle {
                        Text(sub)
                            .miraTimestamp()
                            .lineLimit(1)
                    }
                }
                Spacer()
                if project.conversationCount > 0 {
                    Text("\(project.conversationCount)")
                        .font(Font.sidebarMeta)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.borderSubtle.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                vm.deleteProject(project.id)
            } label: {
                Label("Delete project", systemImage: "trash")
            }
        }
    }

    private var addProjectButton: some View {
        Button {
            showAddProject = true
        } label: {
            Label("Add project", systemImage: "plus.circle")
                .font(Font.sidebarTitle)
                .foregroundStyle(Color.appAccent)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // ── iOS header + new chat pill ────────────────────────────────────────────

    #if os(iOS)
    private var iosHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Mira")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: { showMemories = true }) {
                    Image(systemName: "scroll")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Color(uiColor: .systemFill), in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    isRefreshing = true
                    Task {
                        await vm.loadConversations()
                        isRefreshing = false
                    }
                } label: {
                    Group {
                        if isRefreshing {
                            ProgressView()
                            #if os(macOS)
                                .controlSize(.small)
                            #else
                                .scaleEffect(0.7)
                            #endif
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .systemFill), in: Circle())
                }
                .buttonStyle(.plain)
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: connectionIcon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isReachable ? Color.appAccent : .orange)
                            .frame(width: 38, height: 38)
                            .background(Color(uiColor: .systemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                TextField("Search", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
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
            .padding(.bottom, 8)
        }
        .background(Color.appBg)
    }

    private var iosNewChatPill: some View {
        HStack {
            Spacer()
            Button(action: {
                if let onNewChat { onNewChat() } else { vm.newConversation() }
            }) {
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
        .padding(.vertical, 16)
        .background(Color.appBg)
    }
    #endif

    // ── Conversation row ──────────────────────────────────────────────────────

    private func conversationRow(_ conv: Conversation, isSelected: Bool = false, titleOnly: Bool = false) -> some View {
        let isLoading = vm.loadingConvId == conv.id
        #if os(iOS)
        let project = conv.projectId.flatMap { pid in vm.projects.first(where: { $0.id == pid }) }
        #endif
        #if os(macOS)
        let rowFill: Color = isSelected ? Color.primary.opacity(0.08) : .clear
        #else
        let rowFill: Color = isSelected ? Color.appAccent.opacity(0.14) : .clear
        #endif
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conv.title)
                    .font(Font.sidebarTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !titleOnly {
                    HStack(spacing: 6) {
                        if isLoading {
                            Text("Opening…")
                                .font(Font.sidebarSubtitle)
                                .foregroundStyle(Color.appAccent.opacity(0.7))
                        } else {
                            Text(relativeDate(conv.updatedAt))
                                .miraTimestamp()
                        }
                        #if os(iOS)
                        if let proj = project {
                            Text(proj.name)
                                .font(Font.sidebarMeta)
                                .foregroundStyle(Color.appAccent.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.appAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        #endif
                    }
                }
            }
            Spacer()
            if isLoading {
                ProgressView()
                #if os(macOS)
                    .controlSize(.small)
                #else
                    .scaleEffect(0.7)
                #endif
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rowFill)
        )
        #if os(macOS)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        #else
        .contentShape(Rectangle())
        #endif
        .simultaneousGesture(TapGesture().onEnded {
            vm.selectConversation(conv.id)
            onTap?(conv.id)
        })
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
            Button(role: .destructive) {
                requestDelete(conv)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func relativeDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// ── Add Project sheet ─────────────────────────────────────────────────────────

struct AddProjectSheet: View {
    @Environment(ChatViewModel.self) private var vm
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var localPath = ""
    @State private var githubRepo = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    private var isValidGithubRepo: Bool {
        let gh = githubRepo.trimmingCharacters(in: .whitespaces)
        guard !gh.isEmpty else { return true }
        return gh.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lp = localPath.trimmingCharacters(in: .whitespaces)
        let gh = githubRepo.trimmingCharacters(in: .whitespaces)
        return !n.isEmpty && (!lp.isEmpty || !gh.isEmpty) && isValidGithubRepo
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project name") {
                    TextField("e.g. my-app", text: $name)
                }
                Section {
                    #if os(macOS)
                    HStack(spacing: 8) {
                        Text(localPath.isEmpty ? "No folder selected" : localPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(localPath.isEmpty ? Color.textSecondary : Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select Workspace"
                            if panel.runModal() == .OK {
                                localPath = panel.url?.path ?? ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    #else
                    TextField("/path/on/server", text: $localPath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                } header: {
                    Text("Local path")
                } footer: {
                    Text("Absolute path on the server machine. Leave empty for GitHub-only.")
                        .foregroundStyle(Color.textSecondary)
                }
                Section {
                    TextField("owner/repo", text: $githubRepo)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("GitHub repo")
                } footer: {
                    if !githubRepo.trimmingCharacters(in: .whitespaces).isEmpty && !isValidGithubRepo {
                        Text("Must be in owner/repo format.")
                            .foregroundStyle(.red)
                    } else {
                        Text("At least one of local path or GitHub repo is required.")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                        #if os(macOS)
                            .controlSize(.small)
                        #else
                            .scaleEffect(0.8)
                        #endif
                    } else {
                        Button("Add") { submit() }
                            .disabled(!canSubmit)
                    }
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        let n  = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lp = localPath.trimmingCharacters(in: .whitespaces)
        let gh = githubRepo.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await vm.addProject(
                    name: n,
                    localPath: lp.isEmpty ? nil : lp,
                    githubRepo: gh.isEmpty ? nil : gh
                )
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
