import SwiftUI

// ── Sidebar ───────────────────────────────────────────────────────────────────

struct ConversationListView: View {
    @Bindable var vm: ChatViewModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var renamingConv: Conversation? = nil
    @State private var renameText: String = ""
    @State private var searchText: String = ""
    @State private var showAddProject = false

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return vm.conversations }
        return vm.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
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
        .background(Color.sidebarBg)
        .navigationTitle("Mira")
        #if os(macOS)
        .safeAreaInset(edge: .top) {
            newChatButton
        }
        .safeAreaInset(edge: .bottom) {
            aboutButton
        }
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        #endif
        .sheet(isPresented: $showAddProject) {
            AddProjectSheet(vm: vm, isPresented: $showAddProject)
        }
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
        List(selection: Binding<String?>(
            get: { vm.currentConvId.isEmpty ? nil : vm.currentConvId },
            set: { if let id = $0 { vm.selectConversation(id) } }
        )) {
            // Projects section
            if !vm.projects.isEmpty {
                Section {
                    ForEach(vm.projects) { project in
                        projectRow(project)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    addProjectButton
                } header: {
                    sectionHeader("Projects")
                }
            }

            // Conversations section
            Section {
                ForEach(filteredConversations) { conv in
                    conversationRow(conv)
                        .tag(conv.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Color.borderSubtle.opacity(0.5))
                }
                if vm.projects.isEmpty {
                    addProjectButton
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                sectionHeader("Conversations")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search conversations")
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
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
    }

    // ── Project rows ──────────────────────────────────────────────────────────

    private func projectRow(_ project: Project) -> some View {
        Button {
            vm.newConversation(projectId: project.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: project.icon)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if let sub = project.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if project.conversationCount > 0 {
                    Text("\(project.conversationCount)")
                        .font(.caption2.weight(.medium))
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
                .font(.subheadline)
                .foregroundStyle(Color.appAccent)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // ── About / New Chat (macOS) ──────────────────────────────────────────────

    #if os(macOS)
    private var aboutButton: some View {
        Button(action: { openWindow(id: "about") }) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.textSecondary)
                Text("About Mira")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.sidebarBg)
    }
    #endif

    private var newChatButton: some View {
        Button(action: { vm.newConversation() }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.appAccent)
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
        let project = conv.projectId.flatMap { pid in vm.projects.first(where: { $0.id == pid }) }
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conv.title)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(relativeDate(conv.updatedAt))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    if let proj = project {
                        Text(proj.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.appAccent.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.appAccent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contextMenu {
            Button {
                renameText = conv.title
                renamingConv = conv
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                vm.deleteConversation(conv.id)
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
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                vm.deleteConversation(conv.id)
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
    @Bindable var vm: ChatViewModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var localPath = ""
    @State private var githubRepo = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    private var canSubmit: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lp = localPath.trimmingCharacters(in: .whitespaces)
        let gh = githubRepo.trimmingCharacters(in: .whitespaces)
        return !n.isEmpty && (!lp.isEmpty || !gh.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project name") {
                    TextField("e.g. my-app", text: $name)
                }
                Section {
                    TextField("/Users/you/Projects/my-app", text: $localPath)
                        .autocorrectionDisabled()
                        #if os(iOS)
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
                    Text("At least one of local path or GitHub repo is required.")
                        .foregroundStyle(Color.textSecondary)
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
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
                        ProgressView().scaleEffect(0.8)
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
