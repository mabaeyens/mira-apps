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

            // ── System-memory advisory ────────────────────────────────────
            // Gated on backendReady: if the backend is down the user already has
            // a banner saying so, and a second one about that machine's memory
            // adds noise without adding information. No animation on purpose —
            // the advisory can flip in a single poll and this must not flash.
            if vm.backendReady, let advisory = vm.memoryAdvisory.advisoryText {
                MemoryAdvisoryBanner(text: advisory)
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
                    .padding(.horizontal, Spacing.ml)
                    .padding(.vertical, Spacing.xs)
                }
                .background(Color.appBg)
            }

            // ── Messages + floating pill ──────────────────────────────────
            ZStack(alignment: .top) {
                MessageListView(
                    messages: vm.messages,
                    conversationId: vm.currentConvId.isEmpty ? nil : vm.currentConvId,
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
                LinearGradient(
                    colors: [Color.appBg, Color.appBg.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 72)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
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
                backendPresets: vm.backendPresets,
                isSwitching: vm.isSwitchingBackend,
                switchStatusMessage: vm.switchStatusMessage,
                liveModelName: vm.modelName,
                liveContextWindow: vm.contextWindow,
                library: vm.modelLibrary,
                onSwitch: { backend, modelId in await vm.switchModel(backend: backend, modelId: modelId) }
            )
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showOptions) {
            ConversationOptionsSheet(
                title: currentTitle,
                projects: vm.projects,
                currentProjectId: vm.activeProject?.id,
                onRename: { newTitle in vm.renameConversation(vm.currentConvId, title: newTitle) },
                onDelete: {
                    let id = vm.currentConvId
                    onBack?()
                    vm.deleteConversation(id)
                },
                onAddToProject: { projectId in
                    vm.setProject(projectId, for: vm.currentConvId)
                }
            )
        }
        #endif
        // Destructive-action approval. Both platforms: this is the only control
        // that can authorise a destructive action, so it must never be skipped.
        // The `set` closure is intentionally a no-op — an alert can only be
        // dismissed through one of its buttons, and both buttons clear the
        // queue entry themselves. Declining here instead would decline the
        // *next* queued approval when the user approves the current one.
        .alert(
            vm.pendingApprovals.first?.title ?? "",
            isPresented: Binding(
                get: { vm.pendingApprovals.first != nil },
                set: { _ in }
            ),
            presenting: vm.pendingApprovals.first
        ) { approval in
            Button("Cancel", role: .cancel) { vm.decline(approval) }
            Button("Approve", role: .destructive) { vm.approve(approval) }
        } message: { approval in
            Text(approval.detail)
        }
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
        vm.modelDisplayName.isEmpty ? vm.runningLabel : vm.modelDisplayName
    }

    private var backendLoadingBanner: some View {
        HStack(spacing: Spacing.m) {
            ProgressView()
                .tint(Color.accent)
            #if os(macOS)
                .controlSize(.small)
            #else
                .scaleEffect(0.75)
            #endif
            Text("Model loading…")
                .font(.bannerLabel)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 9)
        .background(Color.accent.opacity(0.06))
        .overlay(alignment: .bottom) {
            Color.accent.opacity(0.2).frame(height: 1)
        }
    }

    private var backendOfflineBanner: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.bannerLabel)
            Text("\(modelLabel) is not running")
                .font(.bannerLabel)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button("Start") {
                Task { await vm.startBackend() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.10))
        .overlay(alignment: .bottom) {
            Color.orange.opacity(0.25).frame(height: 1)
        }
    }

    private var backendStartingBanner: some View {
        HStack(spacing: Spacing.m) {
            ProgressView()
                .tint(.yellow)
            #if os(macOS)
                .controlSize(.small)
            #else
                .scaleEffect(0.75)
            #endif
            Text(vm.switchStatusMessage.isEmpty ? "Starting \(modelLabel)…" : vm.switchStatusMessage)
                .font(.bannerLabel)
                .foregroundStyle(Color.textSecondary)
                .animation(.default, value: vm.switchStatusMessage)
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
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
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.sm)
    }

    private func navCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.rowTitle)
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

/// The memory advisory. Deliberately has no button: there is nothing for the
/// user to do here and nothing for them to dismiss.
///
/// It clears itself, silently and with no congratulation, because the user did
/// nothing to fix it. What does the fixing changed on 2026-08-08: the server now
/// reclaims the model on its own idle branch rather than leaving the bill for
/// whoever asks next. Either way the banner's job is the same — explain an
/// unexplained slowdown while it lasts, then get out of the way.
///
/// A view of its own rather than a method on `ChatView` so that it can be
/// previewed. It is a pure function of one string, but the state that produces
/// that string cannot be reached by using the app: `ChatViewModel.memoryAdvisory`
/// is `private(set)` and only ever set by a 30s poll of the server's own verdict.
/// Extracting the view is the cheap way to see it; a settable advisory or a
/// `#if DEBUG` toggle on the view model would widen a shipping surface to serve
/// a one-off check.
struct MemoryAdvisoryBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "memorychip")
                .foregroundStyle(Color.textSecondary)
                .font(.bannerLabel)
            Text(text)
                .font(.bannerLabel)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.08))
        .overlay(alignment: .bottom) {
            Color.secondary.opacity(0.18).frame(height: 1)
        }
    }
}

/// Every state that renders, at the narrowest width the app supports.
///
/// The strings are read from `advisoryText` rather than typed out, so the
/// preview cannot drift from the shipping copy the way two hand-written copies
/// of the eviction wording already did across mira-apps and mira-core.
///
/// 320pt is deliberate: it is narrower than any supported iPhone, so copy that
/// wraps cleanly here wraps cleanly everywhere. What this shows and the live
/// path does not is layout — that the text wraps rather than truncates, and that
/// the icon stays aligned to the first line rather than centring on a two-line
/// block. What it cannot show is that the poll actually flips the state, which
/// is what the device pass in TEST_PLAN.md is for.
private struct AdvisoryPreview: View {
    var body: some View {
        VStack(spacing: Spacing.xxl) {
            ForEach(MemoryAdvisory.allCases, id: \.rawValue) { advisory in
                if let text = advisory.advisoryText {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(".\(advisory.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        MemoryAdvisoryBanner(text: text)
                    }
                }
            }
        }
        .frame(width: 320)
        .padding(.vertical, Spacing.xxxl)
    }
}

#Preview("Memory advisory — light") {
    AdvisoryPreview().preferredColorScheme(.light)
}

#Preview("Memory advisory — dark") {
    AdvisoryPreview().preferredColorScheme(.dark)
}

// ── Conversation options sheet (iOS) ──────────────────────────────────────────

#if os(iOS)
private struct ConversationOptionsSheet: View {
    let title: String
    let projects: [Project]
    /// The project this conversation is already in, if any. Drives the
    /// checkmark and whether "Remove from project" is offered.
    let currentProjectId: String?
    let onRename: (String) -> Void
    let onDelete: () -> Void
    /// nil means unfile. The server treats an explicit null as "clear the
    /// field", so filing is reversible; without this the control would be
    /// one-way, which is its own kind of trap.
    let onAddToProject: (String?) -> Void

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
                .font(.headline) // 17pt semibold, scales — canonical sheet title (matches InputBar "Add to Chat")
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
                .padding(.vertical, Spacing.xl)

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
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)

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
            HStack(spacing: Spacing.l) {
                Image(systemName: icon)
                    .font(.title3) // 20pt, scales
                    .foregroundStyle(destructive ? .red : Color.textPrimary)
                    .frame(width: 28)
                Text(label)
                    .font(.body) // 17pt, scales
                    .foregroundStyle(destructive ? .red : Color.textPrimary)
                Spacer()
            }
            .padding(.vertical, Spacing.xl)
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
                    List {
                        ForEach(projects) { project in
                            Button(action: {
                                onAddToProject(project.id)
                                showProjectPicker = false
                                dismiss()
                            }) {
                                HStack(spacing: Spacing.ml) {
                                    Image(systemName: project.icon)
                                        .foregroundStyle(Color.appAccent)
                                        .frame(width: 20)
                                    Text(project.name)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if project.id == currentProjectId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(project.id == currentProjectId)
                        }

                        if currentProjectId != nil {
                            Button(action: {
                                onAddToProject(nil)
                                showProjectPicker = false
                                dismiss()
                            }) {
                                HStack(spacing: Spacing.ml) {
                                    Image(systemName: "folder.badge.minus")
                                        .frame(width: 20)
                                    Text("Remove from project")
                                }
                                .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
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
