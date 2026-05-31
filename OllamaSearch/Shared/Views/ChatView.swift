import SwiftUI

/// Main chat content view — message list + input bar.
struct ChatView: View {
    @Environment(ChatViewModel.self) private var vm
    #if os(iOS)
    var onBack: (() -> Void)? = nil
    @State private var showAttachSheet = false
    @State private var showOptions = false
    #endif

    private var currentTitle: String {
        vm.conversations.first(where: { $0.id == vm.currentConvId })?.title ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Backend offline banner ────────────────────────────────────
            if !vm.backendReady && !vm.isSwitchingBackend && !vm.isStartingBackend {
                // Within first 120 s of detecting backend_ready: false, show a gentle
                // spinner banner (model is loading). After that, show the manual-start banner.
                if let since = vm.backendLoadingSince,
                   Date().timeIntervalSince(since) < 120 {
                    backendLoadingBanner
                } else {
                    backendOfflineBanner
                }
            } else if vm.isStartingBackend {
                backendStartingBanner
            }

            // ── Status bar ────────────────────────────────────────────────
            if vm.inputTokens > 0 || vm.outputTokens > 0 {
                HStack {
                    Spacer()
                    StatusBarView(
                        inputTokens: vm.inputTokens,
                        outputTokens: vm.outputTokens,
                        contextPct: vm.contextPct
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background(Color.appBg)
            }

            // ── Messages + floating pill ──────────────────────────────────
            ZStack(alignment: .top) {
                MessageListView(
                    messages: vm.messages,
                    isStreaming: vm.isStreaming,
                    currentSearchQuery: vm.currentSearchQuery,
                    isFetching: vm.isFetching,
                    isLoadingMessages: vm.loadingConvId != nil,
                    failedUserMessageId: vm.lastFailedUserMessage?.id,
                    streamingWaitMessage: vm.streamingWaitMessage,
                    thinkingContent: vm.thinkingContent,
                    isThinkingActive: vm.isThinkingActive,
                    currentToolLabel: vm.currentToolLabel,
                    agentStepLabel: vm.agentStepLabel,
                    topContentInset: {
                        #if os(iOS)
                        return onBack != nil ? 56 : 0
                        #else
                        return 32
                        #endif
                    }(),
                    onResend: { vm.resendLast() },
                    onEdit: { vm.editLast() },
                    onSendSuggestion: { text in
                        vm.inputText = text
                    }
                )
                #if os(iOS)
                if onBack != nil { floatingPillNav }
                #endif
            }

            // ── Input bar ─────────────────────────────────────────────────
            #if os(iOS)
            InputBar(showSheetExternal: $showAttachSheet)
            #else
            InputBar()
            #endif
        }
        .background(Color.appBg)
        #if os(iOS)
        .navigationTitle(onBack == nil ? currentTitle : "")
        #else
        .navigationTitle(currentTitle)
        #endif
        #if os(macOS)
        .sheet(isPresented: Bindable(vm).showModelPicker) {
            ModelPickerView(
                currentBackend: vm.currentBackend,
                currentModelId: vm.modelName,
                isSwitching: vm.isSwitchingBackend,
                switchStatusMessage: vm.switchStatusMessage,
                liveModelName: vm.modelName,
                liveContextWindow: vm.contextWindow,
                onSwitch: { backend, modelId in await vm.switchModel(backend: backend, modelId: modelId) }
            )
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showOptions) {
            ConversationOptionsSheet(
                title: currentTitle,
                projects: vm.projects,
                onRename: { newTitle in vm.renameConversation(vm.currentConvId, title: newTitle) },
                onDelete: {
                    let id = vm.currentConvId
                    onBack?()
                    vm.deleteConversation(id)
                },
                onAddToProject: { _ in /* TODO: backend PATCH /conversations/{id} with project_id */ }
            )
        }
        #endif
        // On iOS the error alert lives in iOSConnectedView so it's reachable
        // whether the sidebar or the detail column is currently visible.
        #if os(macOS)
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        #endif
    }

    // ── Backend banners ───────────────────────────────────────────────────────

    private var modelLabel: String {
        vm.currentBackend == "omlx" ? "Qwen3.6 (oMLX)" : "Qwen3.6 (Ollama)"
    }

    private var backendLoadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.accent)
                .scaleEffect(0.75)
            Text("Model loading…")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accent.opacity(0.06))
        .overlay(alignment: .bottom) {
            Color.accent.opacity(0.2).frame(height: 1)
        }
    }

    private var backendOfflineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text("\(modelLabel) is not running")
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button("Start") {
                Task { await vm.startBackend() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.10))
        .overlay(alignment: .bottom) {
            Color.orange.opacity(0.25).frame(height: 1)
        }
    }

    private var backendStartingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.yellow)
                .scaleEffect(0.75)
            Text(vm.switchStatusMessage.isEmpty ? "Starting \(modelLabel)…" : vm.switchStatusMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .animation(.default, value: vm.switchStatusMessage)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.yellow.opacity(0.08))
        .overlay(alignment: .bottom) {
            Color.yellow.opacity(0.25).frame(height: 1)
        }
    }

    // ── iOS floating pill navigation ──────────────────────────────────────────
    // Floats over the message list in iOSPortraitView.

    #if os(iOS)
    private var floatingPillNav: some View {
        HStack {
            navCircleButton(icon: "chevron.left") { onBack?() }
            Spacer()
            navCircleButton(icon: "ellipsis") { showOptions = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func navCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.borderSubtle.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
    #endif
}

// ── Conversation options sheet (iOS) ──────────────────────────────────────────

#if os(iOS)
private struct ConversationOptionsSheet: View {
    let title: String
    let projects: [Project]
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onAddToProject: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var showDeleteConfirm = false
    @State private var showProjectPicker = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator spacing
            Color.clear.frame(height: 8)

            // Non-tappable title header
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            VStack(spacing: 0) {
                optionRow(icon: "folder.badge.plus", label: "Add to project") {
                    showProjectPicker = true
                }
                Divider().padding(.leading, 52)
                optionRow(icon: "pencil", label: "Rename") {
                    renameText = title
                    showRename = true
                }
                Divider().padding(.leading, 52)
                optionRow(icon: "trash", label: "Delete", destructive: true) {
                    showDeleteConfirm = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    onRename(renameText)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this conversation?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showProjectPicker) {
            projectPickerSheet
        }
    }

    private func optionRow(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(destructive ? .red : Color.textPrimary)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 17))
                    .foregroundStyle(destructive ? .red : Color.textPrimary)
                Spacer()
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private var projectPickerSheet: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(projects) { project in
                        Button(action: {
                            onAddToProject(project.id)
                            showProjectPicker = false
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: project.icon)
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 20)
                                Text(project.name)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showProjectPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif
