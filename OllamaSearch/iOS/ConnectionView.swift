#if os(iOS)
import SwiftUI

struct ConnectionView: View {
    let onConnect: (URL) -> Void

    @Environment(SavedConnectionsStore.self) private var store

    @State private var showAddSheet  = false
    @State private var addURL        = ""
    @State private var addLabel      = ""
    @State private var addError: String? = nil
    @State private var isAddConnecting = false

    @State private var connectingURL: String? = nil
    @State private var rowError: String? = nil

    @State private var showAbout = false

    // nil = not yet probed, true = reachable, false = unreachable
    @State private var reachability: [String: Bool] = [:]

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            RadialGradient(
                colors: [Color.accent.opacity(0.10), .clear],
                center: .init(x: 0.5, y: 0.22),
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                MiraLogoView(size: 100)
                Spacer().frame(height: 18)
                Text("Mira")
                    .font(.bookerly(size: 32, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer().frame(height: 28)

                if !store.connections.isEmpty {
                    List {
                        savedSection
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                } else {
                    tailscaleGuide
                    Spacer()
                }

                Button {
                    addURL = ""
                    addLabel = ""
                    addError = nil
                    showAddSheet = true
                } label: {
                    Label("Add connection", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)

                if let err = rowError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 16)
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
        }
        .sheet(isPresented: $showAddSheet) {
            addConnectionSheet
        }
        .task { await probeAllConnections() }
    }

    // ── Saved connections section ──────────────────────────────────────────

    private var savedSection: some View {
        Section("Saved") {
            ForEach(store.connections) { conn in
                savedRow(conn)
            }
            .onDelete { store.delete(at: $0) }
        }
    }

    private func savedRow(_ conn: SavedConnection) -> some View {
        let isActive  = store.activeURLString == conn.urlString
        let isLoading = connectingURL == conn.urlString
        let reached   = reachability[conn.urlString]

        return HStack(spacing: 12) {
            // Reachability dot: green=up, red=down, gray=unknown
            Circle()
                .fill(reached == true ? Color.green : reached == false ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(conn.label)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accent : Color.textPrimary)
                Text(conn.urlString)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isLoading {
                ProgressView().tint(Color.accent)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { connectRow(urlString: conn.urlString) }
        .listRowBackground(Color.surfaceBg)
    }

    private var isInsecureNonLocal: Bool {
        guard let url = URL(string: addURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" else { return false }
        let host = url.host ?? ""
        return host != "127.0.0.1" && host != "localhost"
    }

    // ── Add connection sheet ───────────────────────────────────────────────

    private var addConnectionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.0.x:8000", text: $addURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: addURL) {
                            if addLabel.isEmpty {
                                addLabel = SavedConnection.autoLabel(for: addURL)
                            }
                            addError = nil
                        }
                } header: {
                    Text("URL")
                } footer: {
                    if isInsecureNonLocal {
                        Text("HTTP traffic over the network is unencrypted. Consider enabling TLS on the server.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("e.g. Home WiFi, Tailscale", text: $addLabel)
                        .autocorrectionDisabled()
                } header: { Text("Label") }
                  footer: { Text("Optional — a name to identify this connection.") }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBg)
            .navigationTitle("Add Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAddConnecting {
                        ProgressView()
                    } else {
                        Button("Connect") { attemptAdd() }
                            .disabled(addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let err = addError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .presentationDetents([.medium])
    }

    // ── Tailscale setup guide ──────────────────────────────────────────────

    private var tailscaleGuide: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text("Connect to your Mac")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.bottom, 10)

            ForEach(Array(setupSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accent)
                        .frame(width: 18, height: 18)
                        .background(Color.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Text(step.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(.bottom, i < setupSteps.count - 1 ? 10 : 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceBg)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderSubtle, lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private struct SetupStep { let title: String; let detail: String }
    private let setupSteps: [SetupStep] = [
        .init(title: "Install Tailscale on your Mac",
              detail: "Download from tailscale.com and sign in with any account."),
        .init(title: "Install Tailscale on this iPhone",
              detail: "App Store → Tailscale. Sign in with the same account."),
        .init(title: "Start Mira on your Mac",
              detail: "Mira runs as a Login Item. Open the Mira app once to register it."),
        .init(title: "Add the Tailscale address below",
              detail: "Tap \"Add connection\" → enter https://<mac-hostname>:8000 (find hostname in Tailscale → your Mac)."),
    ]

    // ── Helpers ────────────────────────────────────────────────────────────

    private func connectRow(urlString: String) {
        guard let url = URL(string: urlString), connectingURL == nil else { return }
        connectingURL = urlString
        rowError = nil
        Task {
            let ok = await APIClient.shared.probe(url)
            await MainActor.run {
                connectingURL = nil
                if ok {
                    store.setActive(urlString)
                    onConnect(url)
                } else {
                    rowError = "Could not reach \(urlString). Check the URL and your connection."
                }
            }
        }
    }

    private func probeAllConnections() async {
        await withTaskGroup(of: (String, Bool).self) { group in
            for conn in store.connections {
                guard let url = conn.url else { continue }
                group.addTask {
                    let ok = await APIClient.shared.probe(url, deadline: 3)
                    return (conn.urlString, ok)
                }
            }
            for await (urlString, ok) in group {
                reachability[urlString] = ok
            }
        }
    }

    private func attemptAdd() {
        let trimmedURL = addURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              url.scheme == "http" || url.scheme == "https" else {
            addError = "Enter a valid http or https URL."
            return
        }
        isAddConnecting = true
        addError = nil
        Task {
            let ok = await APIClient.shared.probe(url)
            await MainActor.run {
                isAddConnecting = false
                if ok {
                    let label = addLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let conn = SavedConnection(
                        label: label.isEmpty ? SavedConnection.autoLabel(for: trimmedURL) : label,
                        urlString: trimmedURL
                    )
                    store.add(conn)
                    store.setActive(trimmedURL)
                    showAddSheet = false
                    onConnect(url)
                } else {
                    addError = "Could not reach server. Check the URL and your connection."
                }
            }
        }
    }
}

#endif
