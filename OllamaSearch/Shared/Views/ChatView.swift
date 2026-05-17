import SwiftUI

/// Main chat content view — message list + input bar.
struct ChatView: View {
    @Bindable var vm: ChatViewModel

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
            }

            // ── Messages ──────────────────────────────────────────────────
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
                onResend: { vm.resendLast() },
                onEdit: { vm.editLast() }
            )

            // ── Input bar ─────────────────────────────────────────────────
            InputBar(vm: vm)
        }
        .background(Color.appBg)
        .navigationTitle(currentTitle)
        .sheet(isPresented: $vm.showModelPicker) {
            ModelPickerView(
                currentBackend: vm.currentBackend,
                isSwitching: vm.isSwitchingBackend,
                switchStatusMessage: vm.switchStatusMessage,
                liveModelName: vm.modelName,
                liveContextWindow: vm.contextWindow,
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
