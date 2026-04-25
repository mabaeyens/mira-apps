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
            AboutView().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddSheet) {
            addConnectionSheet
        }
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

        return HStack(spacing: 12) {
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
                } header: { Text("URL") }

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
