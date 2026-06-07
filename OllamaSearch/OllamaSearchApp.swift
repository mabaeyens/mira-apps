import SwiftUI
import UniformTypeIdentifiers
import CoreText

@main
struct OllamaSearchApp: App {

    // ── macOS ─────────────────────────────────────────────────────────────────
    #if os(macOS)
    @State private var chatVM = ChatViewModel()
    @State private var cloudPrefs = CloudPreferences()

    var body: some Scene {
        WindowGroup {
            MacRootView()
            .frame(minWidth: 700, minHeight: 500)
            .environment(chatVM)
            .environment(cloudPrefs)
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
                .frame(width: 480, height: 560)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(onNewConversation: { chatVM.newConversation() })
        } label: {
            Image(systemName: "sparkle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accent)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        // macOS ignores the Info.plist `UIAppFonts` key (that's iOS-only), so the
        // bundled Lora variable fonts must be registered manually — otherwise
        // `.custom("Lora", …)` silently falls back to the system font.
        Self.registerBundledFonts()
        MacConnectionManager.shared.start()
    }

    /// Register the bundled Lora variable fonts with the process so the brand
    /// font resolves on macOS. Idempotent — repeat calls are no-ops.
    private static func registerBundledFonts() {
        for name in ["Lora[wght]", "Lora-Italic[wght]"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    #endif

    // ── iOS ───────────────────────────────────────────────────────────────────
    #if os(iOS)
    @State private var chatVM = ChatViewModel()
    @State private var connectionsStore = SavedConnectionsStore()
    @State private var cloudPrefs = CloudPreferences()
    @State private var activeURL: URL? = nil
    @State private var splashDone = false
    @State private var showingConnectionSettings = false
    @State private var splashStatus: String = ""
    @State private var isReachable = true
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectMessage: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !splashDone {
                    iOSSplashView(status: splashStatus)
                } else if let url = activeURL {
                    iOSConnectedView(serverURL: url,
                                     isReachable: isReachable, reconnectMessage: reconnectMessage) {
                        showingConnectionSettings = true
                    }
                    .sheet(isPresented: $showingConnectionSettings) {
                        ConnectionView { newURL, token in
                            reconnectTask?.cancel()
                            reconnectTask = nil
                            reconnectMessage = nil
                            isReachable = true
                            APIClient.shared.authToken = token
                            APIClient.shared.baseURL = newURL
                            activeURL = newURL
                            showingConnectionSettings = false
                        }
                        .environment(connectionsStore)
                    }
                } else {
                    ConnectionView { url, token in
                        APIClient.shared.authToken = token
                        APIClient.shared.baseURL = url
                        activeURL = url
                    }
                    .environment(connectionsStore)
                }
            }
            .task {
                async let found = autoConnect()
                try? await Task.sleep(for: .milliseconds(1_400))
                let url = await found
                withAnimation(.easeOut(duration: 0.4)) {
                    if let url {
                        APIClient.shared.authToken = connectionsStore.token(for: url.absoluteString)
                        APIClient.shared.baseURL = url
                        activeURL = url
                    }
                    splashDone = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, splashDone, activeURL != nil else { return }
                startReconnect()
            }
            .environment(chatVM)
            .environment(cloudPrefs)
        }
    }

    /// Called when the app foregrounds. Polls the server for up to 90 s, cycling
    /// through patience messages. Handles three states:
    ///   .ready      → clear banner, reload conversations
    ///   .starting   → server is up but Ollama is still loading; stay on same URL
    ///   .unavailable → try other saved connections; keep waiting
    private func startReconnect() {
        guard let current = activeURL else { return }

        // Quick optimistic probe first — if the server is already up don't flash the banner.
        // Use a short fence so we only show the banner when we actually need it.
        reconnectTask?.cancel()
        reconnectTask = Task {
            let quickOK = await APIClient.shared.probe(current, deadline: 2)
            if quickOK {
                isReachable = true
                reconnectMessage = nil
                return
            }

            isReachable = false
            reconnectMessage = Self.reconnectMessages.randomElement()

            let deadline = Date.now.addingTimeInterval(90)
            while Date.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }

                let status = await APIClient.shared.startupStatus()
                switch status {
                case .ready:
                    isReachable = true
                    reconnectMessage = nil
                    await chatVM.loadBackend()
                    await chatVM.refreshBackendHealth()
                    chatVM.startHealthPolling()
                    await chatVM.loadConversations()
                    return
                case .starting:
                    // Server is responding (503) — Ollama is loading. Stay on same URL.
                    reconnectMessage = Self.reconnectMessages.randomElement()
                case .unavailable:
                    // No response at all — try other saved connections.
                    reconnectMessage = Self.reconnectMessages.randomElement()
                    if let found = await autoConnect() {
                        APIClient.shared.authToken = connectionsStore.token(for: found.absoluteString)
                        APIClient.shared.baseURL = found
                        activeURL = found
                        isReachable = true
                        reconnectMessage = nil
                        await chatVM.loadBackend()
                        await chatVM.refreshBackendHealth()
                        chatVM.startHealthPolling()
                        await chatVM.loadConversations()
                        return
                    }
                }
            }

            // Gave up — clear banner, icon stays orange.
            reconnectMessage = nil
        }
    }

    /// Tries the active saved connection first, then falls through to others.
    private func autoConnect() async -> URL? {
        let isLoopback: (URL) -> Bool = { ["127.0.0.1", "::1"].contains($0.host ?? "") }

        // Try the last-used URL first
        if let active = connectionsStore.activeURLString,
           let url = URL(string: active), !isLoopback(url) {
            splashStatus = "Connecting…"
            if await APIClient.shared.probe(url, deadline: 5) {
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
            if await APIClient.shared.probe(url, deadline: 5) {
                connectionsStore.setActive(conn.urlString)
                splashStatus = "Connected"
                return url
            }
        }
        splashStatus = ""
        return nil
    }

    // ── Server startup / reconnect patience messages ──────────────────────────

    private static let reconnectMessages: [String] = [
        // Server / Ollama startup
        "Server is starting up…",
        "Loading the Ollama model into memory…",
        "Ollama is initializing…",
        "Warming up the model — this takes a moment after sleep",
        "Model weights are being loaded…",
        "Ollama needs 15–30 seconds after a long sleep",
        "Server process is coming online…",
        "The model is being pulled into RAM…",
        "Ollama is preparing your model…",
        "Server startup in progress…",
        "Loading model into memory — almost there",
        "Server is getting ready…",
        "Initializing the language model…",
        "Ollama is doing its thing…",
        "Model load in progress…",
        // Mac waking up
        "Mac is waking from sleep…",
        "Give the Mac a moment to fully wake up",
        "The Mac may still be starting its network stack",
        "System is coming back online after sleep…",
        "Mac's network is settling after sleep…",
        "Waking the system takes a few seconds…",
        "The Mac went to sleep — it's waking now",
        "Waiting for the Mac to fully come online",
        "System wake-up in progress…",
        "Mac is back — waiting for services to start",
        // Network
        "Reconnecting over your network…",
        "Waiting for the connection to stabilize…",
        "Network is settling…",
        "Establishing connection…",
        "Reaching out to your server…",
        "Trying to connect — hang tight",
        "Locating your server on the network…",
        "Connection in progress…",
        "Looking for your Mira server…",
        "Checking available connections…",
        // Local AI / privacy themed
        "Local AI means no cloud — and occasionally a wait",
        "This is the small price of full privacy",
        "Your data never left your Mac — worth the wait",
        "On-device AI, on-device startup time",
        "100% local means 100% patient",
        "Private and worth waiting for",
        "No subscriptions, just a startup delay",
        "The model runs on your hardware — it needs a moment",
        "Local AI: slower to start, faster once running",
        "Worth the wait — everything stays on your device",
        "No rate limits, no cloud, occasional startup delay",
        "Local means private — and a brief wait",
        // Progress-flavored
        "Almost there…",
        "Just a few more seconds…",
        "Still working on it…",
        "Hang tight…",
        "Won't be long now…",
        "Getting there…",
        "Stay with us…",
        "Nearly ready…",
        "One moment please…",
        "Please be patient…",
        "Preparing your assistant…",
        "Setting things up…",
        "Starting your local AI…",
        "Your assistant is waking up…",
        "Give it just a moment…",
        "Taking just a moment…",
        "Almost up and running…",
        "Should be ready shortly…",
        "This is a one-time wait after sleep",
        "Just getting warmed up…",
        "System is back, loading services…",
        "A few more seconds and you're good to go",
        "The server is booting up…",
        "Loading your AI assistant…",
        "Your local AI is coming online…",
        "Mira is starting up…",
        // Connected but loading
        "Connection established — loading model…",
        "Server responded — Ollama is initializing…",
        "Almost done starting up…",
        "The hard part is done — model is loading…",
        "Connected to server — warming up model…",
        "Server is online — model loading in progress…",
        "Reached the server — model startup in progress…",
        "Network is connected — waiting for Ollama…",
        "Found your server — starting the model…",
        "Server located — now loading model…",
        "On the right track — just loading the model",
        "Connection found — finishing startup…",
        "Almost there — model is nearly ready…",
        "Final steps of startup…",
        "Model is almost loaded…",
        "Just the last bit of loading…",
        "Inference engine is starting…",
        "Almost ready to take your questions…",
        "Your AI is almost ready to think…",
        "Completing startup sequence…",
        "Tokens will flow soon…",
        "The wait is nearly over…",
        "Finishing startup…",
        "Your assistant is almost awake…",
        "Ready in just a moment…",
        "Still warming up the model…",
        "Holding on — server is nearly ready",
        "Mira is on its way…",
        "Patience — you'll be chatting soon",
        "Almost at the finish line…",
    ]
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
    @Environment(ChatViewModel.self) private var chatVM

    private let connection = MacConnectionManager.shared
    @State private var splashMinimumElapsed = false
    @State private var showSidebar = true
    @State private var showMemories = false

    private var showMain: Bool {
        if case .ready = connection.state, splashMinimumElapsed { return true }
        return false
    }

    var body: some View {
        Group {
            if showMain {
                HStack(spacing: 0) {
                    if showSidebar {
                        // Floating sidebar card (Claude model): all four corners rounded at the
                        // same radius, even 10pt margin on every side. It sits fully below the
                        // normal title bar, so nothing overlaps its top corners.
                        ConversationListView()
                            .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
                            .padding(10)
                            .transition(.move(edge: .leading))
                    }
                    NavigationStack {
                        ChatView()
                            .toolbar {
                                ToolbarItem(placement: .navigation) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            showSidebar.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "sidebar.left")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
                                }
                                ToolbarItem(placement: .navigation) {
                                    Button {
                                        chatVM.newConversation()
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .help("New Chat")
                                }
                                ToolbarItem(placement: .navigation) {
                                    Button {
                                        showMemories = true
                                    } label: {
                                        Image(systemName: "scroll")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .help("Memories")
                                }
                            }
                    }
                }
                .background(Color.appBg)
                .background(NormalTitleBar())
                .toolbarBackground(Color.appBg, for: .windowToolbar)
                .sheet(isPresented: $showMemories) {
                    MemoriesView()
                }
                .task {
                    await chatVM.loadBackend()
                    await chatVM.refreshBackendHealth()
                    chatVM.startHealthPolling()
                    await chatVM.loadProjects()
                    await chatVM.loadConversations()
                }
            } else {
                SplashView(state: connection.state) {
                    connection.retry()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showMain)
        .task {
            try? await Task.sleep(for: .milliseconds(1_000))
            splashMinimumElapsed = true
        }
    }
}

struct MenuBarContent: View {
    let onNewConversation: () -> Void
    private let connection = MacConnectionManager.shared

    var body: some View {
        Label(statusLabel, systemImage: statusIcon)
            .foregroundStyle(statusColor)
        Divider()
        Button("New Chat") { onNewConversation() }
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
                    .font(.brandTitle)
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
    @Environment(ChatViewModel.self) private var chatVM
    let serverURL: URL
    var isReachable: Bool = true
    var reconnectMessage: String? = nil
    let onSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    /// "Tailscale" for 100.x addresses or *.ts.net hostnames, "Local" otherwise.
    private var connectionLabel: String {
        guard let host = serverURL.host else { return "Server" }
        let isTailscale = host.hasPrefix("100.") || host.hasSuffix(".ts.net")
        return isTailscale ? "Tailscale" : "Local"
    }
    private var connectionIcon: String {
        connectionLabel == "Tailscale" ? "network" : "wifi"
    }

    @ViewBuilder
    private var modelPickerSheet: some View {
        ModelPickerView(
            currentBackend: chatVM.currentBackend,
            currentModelId: chatVM.modelName,
            isSwitching: chatVM.isSwitchingBackend,
            switchStatusMessage: chatVM.switchStatusMessage,
            liveModelName: chatVM.modelName,
            liveContextWindow: chatVM.contextWindow,
            onSwitch: { backend, modelId in await chatVM.switchModel(backend: backend, modelId: modelId) }
        )
        #if os(iOS)
        .presentationBackground(Color.appBg)
        #endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad / iPhone landscape: NavigationSplitView
                // IMPORTANT: do NOT add .toolbar to ConversationListView inside a
                // NavigationStack — iOS 26 treats a toolbar on the root as a column
                // anchor and shows both root and destination side-by-side.
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ConversationListView(onTap: { _ in
                        columnVisibility = .detailOnly
                    })
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { onSettings() } label: {
                                    Image(systemName: connectionIcon)
                                        .foregroundStyle(isReachable ? Color.accent : .orange)
                                }
                                .help(isReachable ? connectionLabel : "\(connectionLabel) — reconnecting…")
                            }
                        }
                } detail: {
                    ChatView()
                }
            } else {
                // iPhone portrait: ZStack overlay — sidebar slides in from the left.
                // No NavigationStack root needed; avoids iOS 26 split-column trap.
                iOSPortraitView(
                    isReachable: isReachable,
                    connectionIcon: connectionIcon,
                    onSettings: onSettings
                )
            }
        }
        .sheet(isPresented: Bindable(chatVM).showModelPicker) { modelPickerSheet }
        .alert("Error", isPresented: Binding(
            get: { chatVM.errorMessage != nil },
            set: { if !$0 { chatVM.errorMessage = nil } }
        )) {
            Button("OK") { chatVM.errorMessage = nil }
        } message: {
            Text(chatVM.errorMessage ?? "")
        }
        .task {
            APIClient.shared.baseURL = serverURL
            await chatVM.loadBackend()
            await chatVM.refreshBackendHealth()
            chatVM.startHealthPolling()
            await chatVM.loadProjects()
            await chatVM.loadConversations()
            // iPad / landscape: auto-select first conversation so detail column isn't blank.
            // Portrait iPhone shows the welcome screen instead — no auto-select.
            if horizontalSizeClass == .regular {
                if chatVM.currentConvId.isEmpty, let first = chatVM.conversations.first {
                    chatVM.selectConversation(first.id)
                }
                columnVisibility = .all
            }
        }
        .onChange(of: chatVM.currentConvId) { _, newId in
            if !newId.isEmpty && horizontalSizeClass == .regular {
                columnVisibility = .detailOnly
            }
        }
        .onAppear {
            if horizontalSizeClass == .regular {
                columnVisibility = .all
            }
        }
        .onChange(of: horizontalSizeClass) { _, newClass in
            columnVisibility = (newClass == .regular) ? .all : .detailOnly
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            reconnectBanner
        }
        .animation(.easeInOut(duration: 0.3), value: reconnectMessage != nil)
    }

    @ViewBuilder
    private var reconnectBanner: some View {
        if let msg = reconnectMessage {
            HStack(spacing: 10) {
                ProgressView()
                #if os(macOS)
                    .controlSize(.small)
                #else
                    .scaleEffect(0.75)
                #endif
                    .tint(Color.accent)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Color.borderSubtle.frame(height: 0.5)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// ── iPhone portrait: ZStack overlay navigation ────────────────────────────────
// Sidebar slides in from the left over a dim scrim.
// WelcomeView shown when no conversation is active; ChatView otherwise.

private struct iOSPortraitView: View {
    @Environment(ChatViewModel.self) private var chatVM
    var isReachable: Bool
    var connectionIcon: String
    let onSettings: () -> Void

    @State private var showSidebar = false

    private func openSidebar() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(.easeInOut(duration: 0.25)) { showSidebar = true }
    }

    private func closeSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) { showSidebar = false }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // ── Main content ──────────────────────────────────────────────
            Group {
                if chatVM.currentConvId.isEmpty && !chatVM.isStreaming && chatVM.messages.isEmpty {
                    WelcomeView(
                        onMenu: openSidebar
                    )
                    .transition(.opacity)
                } else {
                    ChatView(
                        onBack: { openSidebar() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: chatVM.currentConvId.isEmpty && chatVM.messages.isEmpty)

            // ── Sidebar overlay ───────────────────────────────────────────
            if showSidebar {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeSidebar() }
                    .transition(.opacity)

                ConversationListView(
                    onTap: { convId in
                        chatVM.selectConversation(convId)
                        closeSidebar()
                    },
                    onSettings: onSettings,
                    isReachable: isReachable,
                    connectionIcon: connectionIcon,
                    onNewChat: {
                        chatVM.prepareForNewConversation()
                        closeSidebar()
                    }
                )
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }
                .background(Color.appBg)
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
        .onChange(of: showSidebar) { _, shown in
            if shown { Task { await chatVM.loadConversations() } }
        }
    }
}
#endif
