import SwiftUI

/// Main chat content view — message list + input bar.
/// Platform-specific: `attachPicker` is injected by macOS/iOS app entry points.
struct ChatView: View {
    @Bindable var vm: ChatViewModel
    let attachPicker: AnyView

    private var currentTitle: String {
        vm.conversations.first(where: { $0.id == vm.currentConvId })?.title ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Backend offline banner ────────────────────────────────────
            if !vm.backendReady && !vm.isSwitchingBackend && !vm.isStartingBackend {
                backendOfflineBanner
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
                Color.borderSubtle.frame(height: 1)
            }

            // ── Messages ──────────────────────────────────────────────────
            MessageListView(
                messages: vm.messages,
                isStreaming: vm.isStreaming,
                currentSearchQuery: vm.currentSearchQuery,
                isFetching: vm.isFetching,
                currentToolLabel: vm.currentToolLabel,
                isLoadingMessages: vm.loadingConvId != nil,
                failedUserMessageId: vm.lastFailedUserMessage?.id,
                streamingWaitMessage: vm.streamingWaitMessage,
                thinkingContent: vm.thinkingContent,
                isThinkingActive: vm.isThinkingActive,
                onResend: { vm.resendLast() },
                onEdit: { vm.editLast() }
            )

            Color.borderSubtle.frame(height: 1)

            // ── Active project pill ───────────────────────────────────────
            if let project = vm.activeProject {
                HStack(spacing: 4) {
                    Image(systemName: project.localPath != nil ? "folder" : "network")
                        .font(.system(size: 11, weight: .medium))
                    Text(project.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.appAccent.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 5)
                .padding(.bottom, 1)
                .background(Color.appBg)
            }

            // ── Input bar ─────────────────────────────────────────────────
            InputBar(
                text: $vm.inputText,
                thinkingEnabled: $vm.thinkingEnabled,
                stagedNames: vm.stagedAttachmentNames,
                isStreaming: vm.isStreaming,
                onSend: { vm.send() },
                onStop: { vm.stopStreaming() },
                onRemoveAttachment: { idx in
                    vm.pendingAttachments.remove(at: idx)
                    vm.stagedAttachmentNames.remove(at: idx)
                },
                attachPicker: attachPicker
            )
        }
        .background(Color.appBg)
        .navigationTitle(currentTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    vm.showModelPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(modelStatusColor)
                            .frame(width: 7, height: 7)
                        Image(systemName: vm.currentBackend == "omlx" ? "cpu" : "circle.hexagongrid")
                            .font(.system(size: 13, weight: .medium))
                        Text(vm.currentBackend == "omlx" ? "Qwen3.6 (oMLX)" : "Qwen3.6")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.surfaceBg)
                            .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.7), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isSwitchingBackend)
                #if os(macOS)
                .help(modelStatusHelp)
                #endif
            }
        }
        .sheet(isPresented: $vm.showModelPicker) {
            ModelPickerView(
                currentBackend: vm.currentBackend,
                isSwitching: vm.isSwitchingBackend,
                switchStatusMessage: vm.switchStatusMessage,
                onSwitch: { backend in await vm.switchBackend(to: backend) }
            )
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
        vm.currentBackend == "omlx" ? "Qwen3.6 (oMLX)" : "Qwen3.6 (Ollama)"
    }

    private var modelStatusColor: Color {
        if vm.errorMessage != nil { return .red }
        if vm.isSwitchingBackend || vm.isStartingBackend { return .yellow }
        if vm.backendReady { return .green }
        return Color(white: 0.45)
    }

    private var modelStatusHelp: String {
        if let err = vm.errorMessage { return "Error: \(err)" }
        if vm.isSwitchingBackend || vm.isStartingBackend { return "Starting model…" }
        return vm.backendReady ? "Online — tap to switch model" : "Offline — tap to start"
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
}
