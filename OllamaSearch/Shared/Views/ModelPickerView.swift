import SwiftUI

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let currentBackend: String
    let currentModelId: String
    let isSwitching: Bool
    let switchStatusMessage: String
    let liveModelName: String
    let liveContextWindow: Int
    let onSwitch: (String, String) async -> Void  // (backend, modelId)

    @State private var pendingEntry: ModelEntry? = nil
    @State private var models: ModelsResponse? = nil
    @State private var loadError: String? = nil
    @State private var showAddModel = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Switch Model")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isSwitching)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().background(Color.borderSubtle)

            if isSwitching {
                switchingView
            } else if let pending = pendingEntry {
                confirmationView(for: pending)
            } else {
                modelListView
            }
        }
        #if os(macOS)
        .frame(width: 340)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(Color.appBg)
        .task { await loadModels() }
        .onChange(of: isSwitching) { _, switching in
            if switching { pendingEntry = nil }
        }
        .sheet(isPresented: $showAddModel) {
            AddModelView(onAdd: { modelId in
                showAddModel = false
                Task { await loadModels() }
            })
        }
    }

    // ── Switching progress ────────────────────────────────────────────────────

    private var switchingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.yellow)
            Text(switchStatusMessage.isEmpty ? "Switching model…" : switchStatusMessage)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .animation(.default, value: switchStatusMessage)
            Text("Chat is paused during the switch.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    // ── Confirmation ──────────────────────────────────────────────────────────

    private func confirmationView(for entry: ModelEntry) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Switch to \(entry.displayName)?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text("The current model will stop and \(entry.displayName) will load. Chat is paused for 30–60 seconds.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Cancel") { pendingEntry = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.surfaceBg)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle, lineWidth: 1))
                    )

                Button("Switch") {
                    let e = entry
                    pendingEntry = nil
                    Task { await onSwitch(e.backend, e.modelId) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.appAccent))
            }
        }
        .padding(20)
    }

    // ── Model list ────────────────────────────────────────────────────────────

    private var modelListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(20)
                } else if models == nil {
                    ProgressView()
                        .tint(.yellow)
                        .frame(maxWidth: .infinity)
                        .padding(28)
                } else {
                    modelSections
                }

            }
        }
        .frame(maxHeight: 440)
        .background(Color.appBg)
    }

    @ViewBuilder
    private var modelSections: some View {
        if let m = models {
            let validMlx = m.mlxLm.filter {
                !$0.modelId.trimmingCharacters(in: .whitespaces).isEmpty &&
                !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let validOllama = m.ollama.filter {
                !$0.modelId.trimmingCharacters(in: .whitespaces).isEmpty &&
                !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if !validMlx.isEmpty {
                sectionHeader("mlx-lm · Apple Silicon")
                VStack(spacing: 8) {
                    ForEach(validMlx) { entry in modelRow(entry) }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            if !validOllama.isEmpty {
                sectionHeader("Ollama")
                VStack(spacing: 8) {
                    ForEach(validOllama) { entry in modelRow(entry) }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            if validMlx.isEmpty && validOllama.isEmpty {
                Text("No models found locally.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(20)
            }

            // Add model button (mlx-lm only)
            Button {
                showAddModel = true
            } label: {
                Label("Download a model", systemImage: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func modelRow(_ entry: ModelEntry) -> some View {
        let isActive = entry.backend == currentBackend && entry.modelId == currentModelId
        let subtitle = sizeLabel(entry) + " · " + (entry.backend == "mlx-lm" ? "mlx-lm" : "Ollama")
        Button {
            guard !isActive else { return }
            pendingEntry = entry
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isActive && !liveModelName.isEmpty ? liveModelName : entry.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(isActive && liveContextWindow > 0
                         ? "\(subtitle) · \(liveContextWindow / 1024)k ctx"
                         : subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.appAccent.opacity(0.08) : Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isActive ? Color.appAccent.opacity(0.35) : Color.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isActive || isSwitching)
    }

    private func sizeLabel(_ entry: ModelEntry) -> String {
        entry.sizeGb > 0 ? String(format: "%.1f GB", entry.sizeGb) : "? GB"
    }

    // ── Data loading ──────────────────────────────────────────────────────────

    private func loadModels() async {
        do {
            models = try await APIClient.shared.fetchModels()
            loadError = nil
        } catch {
            loadError = "Could not load models: \(error.localizedDescription)"
        }
    }
}

// ── Add Model sheet ───────────────────────────────────────────────────────────

private struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void

    @State private var customId = ""
    @State private var isPulling = false
    @State private var pullPercent: Int = 0
    @State private var pullError: String? = nil

    private let presets: [(id: String, label: String, size: String)] = [
        ("mlx-community/gemma-3-4b-it-4bit",          "Gemma 3 4B (4-bit)",   "2.5 GB"),
        ("mlx-community/gemma-3-12b-it-4bit",         "Gemma 3 12B (4-bit)",  "7.3 GB"),
        ("mlx-community/Mistral-7B-Instruct-v0.3-4bit","Mistral 7B (4-bit)",  "4.1 GB"),
        ("mlx-community/Qwen2.5-14B-Instruct-4bit",   "Qwen 2.5 14B (4-bit)", "8.5 GB"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Download a Model")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isPulling)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().background(Color.borderSubtle)

            ScrollView {
                VStack(spacing: 0) {
                    if isPulling {
                        pullingView
                    } else {
                        presetSection
                        customSection
                    }
                }
            }
        }
        .frame(width: 340)
        .background(Color.appBg)
    }

    private var pullingView: some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(pullPercent), total: 100)
                .tint(Color.appAccent)
                .padding(.horizontal, 20)
            Text("\(pullPercent)% downloaded")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Text("Keep this window open while downloading.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.7))
            if let err = pullError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Dismiss") { isPulling = false; pullError = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POPULAR MODELS")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ForEach(presets, id: \.id) { preset in
                Button {
                    startPull(modelId: preset.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                            Text(preset.size + " · mlx-lm")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(Color.appAccent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 16)
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CUSTOM REPO ID")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            HStack(spacing: 8) {
                TextField("mlx-community/model-name", text: $customId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                Button("Download") {
                    startPull(modelId: customId.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(customId.isEmpty ? Color.textSecondary : Color.appAccent)
                .disabled(customId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func startPull(modelId: String) {
        guard !modelId.isEmpty else { return }
        isPulling = true
        pullPercent = 0
        pullError = nil
        Task {
            do {
                for try await progress in APIClient.shared.pullModel(modelId: modelId) {
                    if let pct = progress.percent { pullPercent = pct }
                    if progress.type == "done" {
                        isPulling = false
                        onAdd(modelId)
                        return
                    }
                    if progress.type == "error" {
                        pullError = progress.message ?? "Download failed."
                        return
                    }
                }
            } catch {
                pullError = error.localizedDescription
            }
        }
    }
}

#Preview {
    ModelPickerView(
        currentBackend: "mlx-lm",
        currentModelId: "mlx-community/gemma-4-26b-a4b-it-4bit",
        isSwitching: false,
        switchStatusMessage: "",
        liveModelName: "Gemma 4 26B",
        liveContextWindow: 65536,
        onSwitch: { _, _ in }
    )
}
