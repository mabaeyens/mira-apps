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
                isLoadingMessages: vm.loadingConvId != nil,
                failedUserMessageId: vm.lastFailedUserMessage?.id,
                streamingWaitMessage: vm.streamingWaitMessage,
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
}
