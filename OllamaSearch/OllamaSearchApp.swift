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

        MenuBarExtra {
            MenuBarContent(chatVM: chatVM, serverManager: ServerManager.shared)
        } label: {
            Image(systemName: "sparkle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
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
    @State private var activeURL: URL? = nil
    @State private var splashDone = false
    @State private var showingConnectionSettings = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !splashDone {
                    iOSSplashView()
                } else if let url = activeURL {
                    iOSConnectedView(chatVM: chatVM, serverURL: url) {
                        showingConnectionSettings = true
                    }
                    .sheet(isPresented: $showingConnectionSettings) {
                        ConnectionView(autoConnect: false) { newURL in
                            APIClient.shared.baseURL = newURL
                            activeURL = newURL
                            showingConnectionSettings = false
                        }
                    }
                } else {
                    ConnectionView { url in
                        APIClient.shared.baseURL = url
                        activeURL = url
                    }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                // Start connection attempt immediately in background.
                async let found = autoConnect()
                // Always show splash for at least 1.4 s.
                try? await Task.sleep(for: .milliseconds(1_400))
                // Collect result (likely already ready by now).
                let url = await found
                withAnimation(.easeOut(duration: 0.4)) {
                    if let url {
                        APIClient.shared.baseURL = url
                        activeURL = url
                    }
                    splashDone = true
                }
            }
        }
    }

    /// Tries the saved local URL first, then the saved remote URL.
    /// Returns the first one that responds, or nil if neither is reachable.
    private func autoConnect() async -> URL? {
        let localURL  = UserDefaults.standard.string(forKey: "localURL").flatMap(URL.init(string:))
        let remoteURL = UserDefaults.standard.string(forKey: "remoteURL").flatMap(URL.init(string:))
        // Skip loopback — a 127.0.0.1 localURL can appear when Bonjour resolved
        // while Tailscale was active; it only works inside that specific VPN tunnel.
        let isLoopback: (URL) -> Bool = { ["127.0.0.1", "::1"].contains($0.host ?? "") }
        if let local = localURL, !isLoopback(local), await APIClient.shared.probe(local, deadline: 2) { return local }
        if let remote = remoteURL, await APIClient.shared.probe(remote, deadline: 2) { return remote }
        return nil
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
    let onSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showAbout = false

    /// "Tailscale" for 100.x addresses or *.ts.net hostnames, "Local" otherwise.
    private var connectionLabel: String {
        guard let host = serverURL.host else { return "Server" }
        let isTailscale = host.hasPrefix("100.") || host.hasSuffix(".ts.net")
        return isTailscale ? "Tailscale" : "Local"
    }
    private var connectionIcon: String {
        connectionLabel == "Tailscale" ? "network" : "wifi"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(vm: chatVM)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { onSettings() } label: {
                            Image(systemName: connectionIcon)
                                .foregroundStyle(Color.accent)
                        }
                        .help(connectionLabel)
                    }
                }
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
            }
        }
        .alert("Error", isPresented: Binding(
            get: { chatVM.errorMessage != nil },
            set: { if !$0 { chatVM.errorMessage = nil } }
        )) {
            Button("OK") { chatVM.errorMessage = nil }
        } message: {
            Text(chatVM.errorMessage ?? "")
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
            if !newId.isEmpty {
                // Dismiss keyboard when switching conversations.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                if horizontalSizeClass != .compact {
                    columnVisibility = .detailOnly
                }
            }
        }
    }
}
#endif
