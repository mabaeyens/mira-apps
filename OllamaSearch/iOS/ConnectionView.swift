#if os(iOS)
import SwiftUI

/// Connection setup screen — shown when no server URL is configured.
/// Supports Bonjour auto-discovery (local WiFi) and manual URL (Tailscale/remote).
struct ConnectionView: View {
    @State private var bonjour = BonjourDiscovery()
    @State private var mode: Mode = .auto
    @State private var manualURL: String = UserDefaults.standard.string(forKey: "remoteURL") ?? ""
    @State private var showAbout = false
    let onConnect: (URL) -> Void

    enum Mode { case auto, manual }

    private var isSearching: Bool { mode == .auto && bonjour.isSearching }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.appBg.ignoresSafeArea()

            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 56)
            .padding(.trailing, 24)
            .zIndex(1)
            .sheet(isPresented: $showAbout) {
                AboutView()
                    .presentationDetents([.medium, .large])
            }

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
        .onAppear {
            if mode == .auto { bonjour.start() }
        }
        .onDisappear { bonjour.stop() }
        .onChange(of: mode) {
            if mode == .auto { bonjour.start() } else { bonjour.stop() }
        }
        .onChange(of: bonjour.discoveredURL) {
            if let url = bonjour.discoveredURL { connectLocal(url) }
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
                Label(url.absoluteString, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accent)
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
            TextField("http://100.x.x.x:8000", text: $manualURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxWidth: 320)
            Button("Connect") {
                guard let url = URL(string: manualURL),
                      url.scheme == "http" || url.scheme == "https" else { return }
                connectRemote(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .disabled(manualURL.isEmpty)
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
