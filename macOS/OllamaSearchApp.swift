import SwiftUI

@main
struct OllamaSearchApp: App {
    @State private var chatVM = ChatViewModel()
    private let serverManager = ServerManager.shared
    @State private var showPathPicker = false

    var body: some Scene {
        // ── Main window ───────────────────────────────────────────────────────
        WindowGroup {
            Group {
                if case .ready = serverManager.state {
                    NavigationSplitView {
                        ConversationListView(vm: chatVM)
                            .frame(minWidth: 200)
                    } detail: {
                        ChatView(
                            vm: chatVM,
                            attachPicker: AnyView(MacAttachButton(vm: chatVM))
                        )
                    }
                    .task {
                        await chatVM.loadConversations()
                        // Set initial conversation from server state
                        if chatVM.currentConvId.isEmpty, let first = chatVM.conversations.first {
                            chatVM.selectConversation(first.id)
                        }
                    }
                } else {
                    SplashView(state: serverManager.state) {
                        showPathPicker = true
                    }
                    .fileImporter(
                        isPresented: $showPathPicker,
                        allowedContentTypes: [.folder]
                    ) { result in
                        if case .success(let url) = result {
                            serverManager.projectPath = url.path
                            UserDefaults.standard.set(url.path, forKey: "projectPath")
                            serverManager.start()
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Chat") { chatVM.newConversation() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }

        // ── Menu bar extra ────────────────────────────────────────────────────
        MenuBarExtra("OllamaSearch", systemImage: "brain.head.profile") {
            MenuBarContent(chatVM: chatVM, serverManager: serverManager)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        ServerManager.shared.start()
    }
}

// ── Menu bar content ──────────────────────────────────────────────────────────

struct MenuBarContent: View {
    let chatVM: ChatViewModel
    let serverManager: ServerManager

    var body: some View {
        VStack {
            // Server status indicator
            Label(statusLabel, systemImage: statusIcon)
                .foregroundStyle(statusColor)

            Divider()

            Button("New Chat") { chatVM.newConversation() }
            Button("Show Window") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var statusLabel: String {
        switch serverManager.state {
        case .idle:            return "Server idle"
        case .starting:        return "Starting…"
        case .waitingForModel: return "Loading model…"
        case .ready:           return "Ready"
        case .failed:          return "Server error"
        }
    }

    private var statusIcon: String {
        switch serverManager.state {
        case .ready:  return "circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        default:      return "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch serverManager.state {
        case .ready:  return .green
        case .failed: return .red
        default:      return .secondary
        }
    }
}
