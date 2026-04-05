import SwiftUI
import UniformTypeIdentifiers

@main
struct OllamaSearchApp: App {

    // ── macOS ─────────────────────────────────────────────────────────────────
    #if os(macOS)
    @State private var chatVM = ChatViewModel()
    @State private var showPathPicker = false

    var body: some Scene {
        WindowGroup {
            MacRootView(
                chatVM: chatVM,
                showPathPicker: $showPathPicker
            )
            .preferredColorScheme(.dark)
            .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
            CommandGroup(after: .newItem) {
                Button("New Chat") { chatVM.newConversation() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Window("About Mira", id: "about") {
            AboutView()
                .frame(width: 480, height: 400)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Mira", systemImage: "eye") {
            MenuBarContent(chatVM: chatVM, serverManager: ServerManager.shared)
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
    @State private var splashDone = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !splashDone {
                    iOSSplashView()
                } else if let url = serverURL {
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
            .task {
                try? await Task.sleep(for: .milliseconds(1_400))
                withAnimation(.easeOut(duration: 0.4)) { splashDone = true }
            }
        }
    }
    #endif
}

// ── About command (macOS) ─────────────────────────────────────────────────────
#if os(macOS)
/// Placed inside CommandGroup so it can access @Environment(\.openWindow).
private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About Mira") { openWindow(id: "about") }
    }
}
#endif

// ── macOS helpers ─────────────────────────────────────────────────────────────
#if os(macOS)

/// Root macOS view. Lives as a proper View (not inline in App.body) so that
/// @Observable property access on ServerManager is correctly tracked and
/// triggers re-renders when state changes.
struct MacRootView: View {
    var chatVM: ChatViewModel
    @Binding var showPathPicker: Bool

    private let serverManager = ServerManager.shared
    @State private var splashMinimumElapsed = false

    var body: some View {
        Group {
            if case .ready = serverManager.state, splashMinimumElapsed {
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
        .task {
            try? await Task.sleep(for: .milliseconds(1_000))
            splashMinimumElapsed = true
        }
    }
}

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
struct iOSSplashView: View {
    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            RadialGradient(
                colors: [Color.accent.opacity(0.10), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                MiraLogoView(size: 100, animated: true)
                Spacer().frame(height: 24)
                Text("Mira")
                    .font(.bookerly(size: 34, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
        }
    }
}
#endif

#if os(iOS)
struct iOSConnectedView: View {
    let chatVM: ChatViewModel
    let serverURL: URL
    let onDisconnect: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(vm: chatVM)
        } detail: {
            ChatView(
                vm: chatVM,
                attachPicker: AnyView(iOSAttachButton(vm: chatVM))
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAbout = true } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { onDisconnect() } label: {
                        Image(systemName: "wifi.slash")
                    }
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .presentationDetents([.medium, .large])
        }
        .task {
            APIClient.shared.baseURL = serverURL
            await chatVM.loadConversations()
            if chatVM.currentConvId.isEmpty, let first = chatVM.conversations.first {
                chatVM.selectConversation(first.id)
            }
        }
        .onChange(of: chatVM.currentConvId) { _, newId in
            if !newId.isEmpty, horizontalSizeClass != .compact {
                columnVisibility = .detailOnly
            }
        }
    }
}
#endif
