import SwiftUI

/// Connection setup screen — shown when no server URL is configured.
/// Supports Bonjour auto-discovery (local WiFi) and manual URL (Tailscale/remote).
struct ConnectionView: View {
    @State private var bonjour = BonjourDiscovery()
    @State private var mode: Mode = .auto
    @State private var manualURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    let onConnect: (URL) -> Void

    enum Mode { case auto, manual }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Connect to OllamaSearch")
                .font(.title2.weight(.semibold))

            Picker("Mode", selection: $mode) {
                Text("Auto (Bonjour)").tag(Mode.auto)
                Text("Manual URL").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            if mode == .auto {
                autoBonjourSection
            } else {
                manualURLSection
            }

            Text("For remote access outside your home network, install Tailscale on both your Mac and iPhone, then use the Manual URL with your Tailscale IP (e.g. http://100.x.x.x:8000).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(32)
        .onAppear {
            if mode == .auto { bonjour.start() }
        }
        .onDisappear { bonjour.stop() }
        .onChange(of: mode) {
            if mode == .auto { bonjour.start() } else { bonjour.stop() }
        }
        .onChange(of: bonjour.discoveredURL) {
            if let url = bonjour.discoveredURL {
                saveAndConnect(url)
            }
        }
    }

    private var autoBonjourSection: some View {
        VStack(spacing: 12) {
            if bonjour.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching on local network…")
                        .foregroundStyle(.secondary)
                }
            } else if let url = bonjour.discoveredURL {
                Label(url.absoluteString, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("No server found. Make sure the Mac is on the same WiFi and the server is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { bonjour.stop(); bonjour.start() }
                    .buttonStyle(.bordered)
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
                saveAndConnect(url)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualURL.isEmpty)
        }
    }

    private func saveAndConnect(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
        onConnect(url)
    }
}
