import SwiftUI
import UniformTypeIdentifiers

@main
struct OllamaSearchApp: App {

    // ── macOS ─────────────────────────────────────────────────────────────────
    #if os(macOS)
    @State private var chatVM = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            MacRootView(chatVM: chatVM)
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
            MenuBarContent(chatVM: chatVM)
        } label: {
            Image(systemName: "sparkle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        MacConnectionManager.shared.start()
    }
    #endif

    // ── iOS ───────────────────────────────────────────────────────────────────
    #if os(iOS)
    @State private var chatVM = ChatViewModel()
    @State private var connectionsStore = SavedConnectionsStore()
    @State private var activeURL: URL? = nil
    @State private var splashDone = false
    @State private var showingConnectionSettings = false
    @State private var splashStatus: String = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if !splashDone {
                    iOSSplashView(status: splashStatus)
                } else if let url = activeURL {
                    iOSConnectedView(chatVM: chatVM, serverURL: url) {
                        showingConnectionSettings = true
                    }
                    .sheet(isPresented: $showingConnectionSettings) {
                        ConnectionView { newURL in
                            APIClient.shared.baseURL = newURL
                            activeURL = newURL
                            showingConnectionSettings = false
                        }
                        .environment(connectionsStore)
                    }
                } else {
                    ConnectionView { url in
                        APIClient.shared.baseURL = url
                        activeURL = url
                    }
                    .environment(connectionsStore)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                async let found = autoConnect()
                try? await Task.sleep(for: .milliseconds(1_400))
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

    /// Tries the active saved connection first, then falls through to others.
    private func autoConnect() async -> URL? {
        let isLoopback: (URL) -> Bool = { ["127.0.0.1", "::1"].contains($0.host ?? "") }

        // Try the last-used URL first
        if let active = connectionsStore.activeURLString,
           let url = URL(string: active), !isLoopback(url) {
            splashStatus = "Connecting…"
            if await APIClient.shared.probe(url, deadline: 2) {
                splashStatus = "Connected"
                return url
            }
        }
        // Fall through to other saved connections
        for conn in connectionsStore.connections {
            guard let url = conn.url,
                  !isLoopback(url),
                  conn.urlString != connectionsStore.activeURLString else { continue }
            splashStatus = "Trying \(conn.label)…"
            if await APIClient.shared.probe(url, deadline: 2) {
                connectionsStore.setActive(conn.urlString)
                splashStatus = "Connected"
                return url
            }
        }
        splashStatus = ""
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
/// @Observable property access on MacConnectionManager is correctly tracked and
/// triggers re-renders when state changes.
struct MacRootView: View {
    var chatVM: ChatViewModel

    private let connection = MacConnectionManager.shared
    @State private var splashMinimumElapsed = false

    var body: some View {
        Group {
            if case .ready = connection.state, splashMinimumElapsed {
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
                    await chatVM.loadProjects()
                    await chatVM.loadConversations()
                    if chatVM.currentConvId.isEmpty,
                       let first = chatVM.conversations.first {
                        chatVM.selectConversation(first.id)
                    }
                }
            } else {
                SplashView(state: connection.state) {
                    connection.retry()
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
    private let connection = MacConnectionManager.shared

    var body: some View {
        Label(statusLabel, systemImage: statusIcon)
            .foregroundStyle(statusColor)
        Divider()
        Button("New Chat") { chatVM.newConversation() }
        Button("Show Window") { NSApplication.shared.activate(ignoringOtherApps: true) }
        if case .failed = connection.state {
            Button("Retry Connection") { connection.retry() }
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private var statusLabel: String {
        switch connection.state {
        case .connecting(let msg): return msg
        case .ready:               return "Ready"
        case .failed:              return "Server not running"
        }
    }
    private var statusIcon: String {
        switch connection.state {
        case .ready:  return "circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        default:      return "circle.dotted"
        }
    }
    private var statusColor: Color {
        switch connection.state {
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
    var status: String = ""

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
                MiraLogoView(size: 140, animated: true, playIntro: true)
                Spacer().frame(height: 28)
                Text("Mira")
                    .font(.bookerly(size: 38, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer().frame(height: 16)
                Text(status.isEmpty ? " " : status)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .animation(.easeInOut(duration: 0.25), value: status)
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
                    HStack(spacing: 4) {
                        Button { chatVM.newConversation() } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        Button { showAbout = true } label: {
                            Image(systemName: "info.circle")
                        }
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
        }
        .task {
            APIClient.shared.baseURL = serverURL
            await chatVM.loadProjects()
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
