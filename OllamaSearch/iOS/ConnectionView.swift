#if os(iOS)
import SwiftUI

/// Connection setup screen — shown when no server URL is configured.
/// Supports Bonjour auto-discovery (local WiFi) and manual URL (Tailscale/remote).
struct ConnectionView: View {
    /// When true (default, cold start), auto-connects as soon as Bonjour finds the server.
    /// When false (opened from gear), shows the found server and waits for a tap.
    let autoConnect: Bool

    init(autoConnect: Bool = true, onConnect: @escaping (URL) -> Void) {
        self.autoConnect = autoConnect
        self.onConnect = onConnect
    }

    @State private var bonjour = BonjourDiscovery()
    @State private var manualURL: String = UserDefaults.standard.string(forKey: "remoteURL") ?? ""
    // Default to manual mode if a remote URL is already saved, so the user
    // sees their Tailscale address immediately instead of waiting for Bonjour.
    @State private var mode: Mode = UserDefaults.standard.string(forKey: "remoteURL") != nil ? .manual : .auto
    @State private var showAbout = false
    @State private var isConnecting = false
    @State private var connectionError: String? = nil
    let onConnect: (URL) -> Void

    enum Mode { case auto, manual }

    private var isSearching: Bool { mode == .auto && bonjour.isSearching }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            // Warm glow anchored near the top where the logo sits
            RadialGradient(
                colors: [Color.accent.opacity(0.10), .clear],
                center: .init(x: 0.5, y: 0.22),
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                MiraLogoView(size: 96, animated: isSearching)

                Spacer().frame(height: 22)

                Text("Mira")
                    .font(.bookerly(size: 32, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer().frame(height: 36)

                Picker("Mode", selection: $mode) {
                    Text("Auto (Bonjour)").tag(Mode.auto)
                    Text("Remote / Tailscale").tag(Mode.manual)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer().frame(height: 28)

                Group {
                    if mode == .auto {
                        autoBonjourSection
                    } else {
                        manualURLSection
                    }
                }
                .frame(minHeight: 72)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .overlay(alignment: .topTrailing) {
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 20)
            .padding(.trailing, 24)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if mode == .auto { bonjour.start() }
        }
        .onDisappear { bonjour.stop() }
        .onChange(of: mode) {
            if mode == .auto { bonjour.start() } else { bonjour.stop() }
        }
        .onChange(of: bonjour.discoveredURL) {
            if autoConnect, let url = bonjour.discoveredURL { connectLocal(url) }
        }
    }

    private var autoBonjourSection: some View {
        VStack(spacing: 12) {
            if bonjour.isSearching {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.accent)
                    Text("Searching on local network…")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            } else if let url = bonjour.discoveredURL {
                VStack(spacing: 10) {
                    Label(url.absoluteString, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accent)
                    if !autoConnect {
                        Button("Connect") { connectLocal(url) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accent)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text("No server found. Make sure your Mac is on the same WiFi and Mira is running.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { bonjour.stop(); bonjour.start() }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                }
            }
        }
    }

    private var manualURLSection: some View {
        VStack(spacing: 12) {
            TextField("https://miguels-macbook-pro.tail51ad7d.ts.net:8443", text: $manualURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxWidth: 320)
                .onChange(of: manualURL) { connectionError = nil }
            Button {
                let trimmed = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed),
                      url.scheme == "http" || url.scheme == "https" else { return }
                isConnecting = true
                connectionError = nil
                Task {
                    if await APIClient.shared.probe(url) {
                        connectRemote(url)
                    } else {
                        isConnecting = false
                        connectionError = "Could not reach server. Check the URL and your connection."
                    }
                }
            } label: {
                if isConnecting {
                    ProgressView().tint(.white)
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .disabled(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
    }

    /// Bonjour-discovered URL — saved as the local (LAN) address.
    private func connectLocal(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "localURL")
        onConnect(url)
    }

    /// Manually entered URL (Tailscale / remote) — saved separately so auto-connect can try both.
    private func connectRemote(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "remoteURL")
        onConnect(url)
    }
}

#endif
