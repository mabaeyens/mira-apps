import SwiftUI

@main
struct OllamaSearchApp: App {

    // ── macOS ─────────────────────────────────────────────────────────────────
    #if os(macOS)
    @State private var chatVM = ChatViewModel()
    private let serverManager = ServerManager.shared
    @State private var showPathPicker = false

    var body: some Scene {
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
                        if chatVM.currentConvId.isEmpty,
                           let first = chatVM.conversations.first {
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

        MenuBarExtra("OllamaSearch", systemImage: "brain.head.profile") {
            MenuBarContent(chatVM: chatVM, serverManager: serverManager)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        ServerManager.shared.start()
    }
    #endif

    // ── iOS ───────────────────────────────────────────────────────────────────
    #if os(iOS)
    @State private var chatVM = ChatViewModel()
    @State private var serverURL: URL? = {
        UserDefaults.standard.string(forKey: "serverURL").flatMap(URL.init(string:))
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = serverURL {
                    iOSConnectedView(chatVM: chatVM, serverURL: url) {
                        UserDefaults.standard.removeObject(forKey: "serverURL")
                        serverURL = nil
                    }
                } else {
                    ConnectionView { url in
                        serverURL = url
                        APIClient.shared.baseURL = url
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    #endif
}

// ── macOS helpers ─────────────────────────────────────────────────────────────
#if os(macOS)
struct MenuBarContent: View {
    let chatVM: ChatViewModel
    let serverManager: ServerManager

    var body: some View {
        Label(statusLabel, systemImage: statusIcon)
            .foregroundStyle(statusColor)
        Divider()
        Button("New Chat") { chatVM.newConversation() }
        Button("Show Window") { NSApplication.shared.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
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
#endif

// ── iOS helpers ───────────────────────────────────────────────────────────────
#if os(iOS)
struct iOSConnectedView: View {
    let chatVM: ChatViewModel
    let serverURL: URL
    let onDisconnect: () -> Void

    var body: some View {
        NavigationSplitView {
            ConversationListView(vm: chatVM)
        } detail: {
            ChatView(
                vm: chatVM,
                attachPicker: AnyView(iOSAttachButton(vm: chatVM))
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { onDisconnect() } label: {
                        Image(systemName: "wifi.slash")
                    }
                }
            }
        }
        .task {
            APIClient.shared.baseURL = serverURL
            await chatVM.loadConversations()
            if chatVM.currentConvId.isEmpty, let first = chatVM.conversations.first {
                chatVM.selectConversation(first.id)
            }
        }
    }
}
#endif
