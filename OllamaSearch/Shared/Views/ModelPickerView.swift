import SwiftUI

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let backendPresets: [BackendPreset]
    let isSwitching: Bool
    let switchStatusMessage: String
    let liveModelName: String
    let liveContextWindow: Int
    /// Local library from `GET /models`, for sizes and for hiding models the
    /// download sheet would otherwise offer to fetch again.
    var library: ModelsResponse? = nil
    let onSwitch: (String, String) async -> Void  // (backend, modelId)

    @State private var pendingPreset: BackendPreset? = nil
    @State private var showAddModel = false

    /// Selectable entries first, then the ones that cannot be switched to.
    /// The server already puts the running model at the top of `available`.
    private var selectable: [BackendPreset] { backendPresets.filter(\.available) }
    private var unselectable: [BackendPreset] { backendPresets.filter { !$0.available } }

    /// Every model id already on disk, so the download sheet does not offer to
    /// fetch something that is sitting there. It used to list Gemma 4 26B as a
    /// suggested download on a machine that already had it.
    private var installedModelIds: Set<String> {
        Set(library?.backends.flatMap { $0.models.map(\.modelId) } ?? [])
    }

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
            } else if let pending = pendingPreset {
                confirmationView(for: pending)
            } else {
                modelListView
            }
        }
        #if os(macOS)
        .frame(width: 340)
        #else
        .frame(maxWidth: .infinity)
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        #endif
        .background(Color.appBg)
        .onChange(of: isSwitching) { _, switching in
            if switching { pendingPreset = nil }
        }
        .sheet(isPresented: $showAddModel) {
            AddModelView(installed: installedModelIds, onAdd: { _ in
                showAddModel = false
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

    private func confirmationView(for preset: BackendPreset) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Switch to \(preset.label)?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text("The current model will stop and \(preset.label) will load. Chat is paused for 30–60 seconds.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Cancel") { pendingPreset = nil }
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
                    let p = preset
                    pendingPreset = nil
                    Task { await onSwitch(p.backend, p.model) }
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
                if backendPresets.isEmpty {
                    Text("No backends configured.\nAdd entries to mira.yaml on the server.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(20)
                } else {
                    if !selectable.isEmpty {
                        sectionHeader("Models")
                        VStack(spacing: 8) {
                            ForEach(selectable) { preset in presetRow(preset) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                    // Shown rather than hidden: a user who put an entry in
                    // mira.yaml deliberately would otherwise think it was lost.
                    if !unselectable.isEmpty {
                        sectionHeader("Not available")
                        VStack(spacing: 8) {
                            ForEach(unselectable) { preset in presetRow(preset) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }

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
        .frame(maxHeight: 440)
        .background(Color.appBg)
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

    /// The model's name, without the parenthetical that mira.yaml labels carry.
    ///
    /// Those parentheticals are engineering notes ("vllm-mlx, patched mistral
    /// tool parser", "mira-mlx, owned server") and they truncated mid-word in a
    /// 340pt sheet. Everything a user decides with — which engine, how much
    /// context, how much disk — is on the subtitle line instead, where it fits.
    private func modelName(_ preset: BackendPreset) -> String {
        if preset.active, !liveModelName.isEmpty {
            return liveModelName.split(separator: "/").last.map(String.init) ?? liveModelName
        }
        guard let paren = preset.label.firstIndex(of: "(") else { return preset.label }
        let trimmed = preset.label[..<paren].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? preset.label : trimmed
    }

    private func subtitle(_ preset: BackendPreset) -> String {
        var parts: [String] = []
        let backend = Backend.label(for: preset.backend)
        if !backend.isEmpty { parts.append(backend) }

        let ctx = preset.active && liveContextWindow > 0 ? liveContextWindow : preset.contextWindow
        if ctx > 0 { parts.append("\(ctx / 1024)k ctx") }

        if let gb = library?.sizeGb(backend: preset.backend, model: preset.model), gb > 0 {
            parts.append(String(format: "%.1f GB", gb))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func presetRow(_ preset: BackendPreset) -> some View {
        Button {
            guard !preset.active, preset.available else { return }
            pendingPreset = preset
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(modelName(preset))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(preset.available ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(1)
                    Text(subtitle(preset))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    // Why it cannot be selected, in the user's terms: "Ollama is
                    // installed but not responding" rather than a row that
                    // simply fails when tapped.
                    if !preset.available, !preset.detail.isEmpty {
                        Text(preset.detail)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if preset.active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                } else if !preset.available {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(preset.active ? Color.appAccent.opacity(0.08) : Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                preset.active ? Color.appAccent.opacity(0.35) : Color.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
            .opacity(preset.available ? 1 : 0.65)
        }
        .buttonStyle(.plain)
        .disabled(preset.active || !preset.available || isSwitching)
    }

}

// ── Add Model sheet ───────────────────────────────────────────────────────────

private struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss
    /// Model ids already on disk. Filtered out of the suggestions below, since
    /// offering to download something the machine already has is noise at best
    /// and a redownload at worst.
    var installed: Set<String> = []
    let onAdd: (String) -> Void

    @State private var customId = ""
    @State private var isPulling = false
    @State private var pullPercent: Int = 0
    @State private var pullError: String? = nil

    private static let allSuggestions: [(id: String, label: String, size: String)] = [
        ("mlx-community/gemma-4-26b-a4b-it-4bit",     "Gemma 4 26B (4-bit)",  "15.6 GB"),
        ("mlx-community/gemma-3-12b-it-4bit",         "Gemma 3 12B (4-bit)",   "7.3 GB"),
        ("mlx-community/Qwen2.5-14B-Instruct-4bit",   "Qwen 2.5 14B (4-bit)",  "8.5 GB"),
        ("mlx-community/Mistral-7B-Instruct-v0.3-4bit","Mistral 7B (4-bit)",   "4.1 GB"),
    ]

    private var presets: [(id: String, label: String, size: String)] {
        Self.allSuggestions.filter { !installed.contains($0.id) }
    }

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

    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POPULAR MODELS")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if presets.isEmpty {
                Text("Every suggested model is already installed. Use a repo id below to download something else.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            ForEach(presets, id: \.id) { preset in
                Button {
                    startPull(modelId: preset.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                            Text(preset.size)
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
        backendPresets: [
            BackendPreset(id: "mira-mlx-qwen3", label: "Qwen3.6 35B", backend: "mira-mlx",
                          model: "mlx-community/Qwen3.6-35B-A3B-4bit", contextWindow: 131072, active: true),
            BackendPreset(id: "omlx-gemma4", label: "Gemma 4 26B", backend: "omlx",
                          model: "gemma4-26b", contextWindow: 65536, active: false),
            BackendPreset(id: "mlxlm-ministral", label: "Ministral 3 14B (mlx-lm, text-only load)",
                          backend: "mlx-lm", model: "mlx-community/Ministral-3-14B-Instruct-2512-4bit",
                          contextWindow: 65536, active: false),
            BackendPreset(id: "ollama-ministral", label: "Ministral 3 14B (Ollama)", backend: "ollama",
                          model: "ministral-3:14b", contextWindow: 131072, active: false,
                          available: false,
                          detail: "Ollama is installed but not responding, start it to see its models"),
        ],
        isSwitching: false,
        switchStatusMessage: "",
        liveModelName: "mlx-community/Qwen3.6-35B-A3B-4bit",
        liveContextWindow: 128000,
        onSwitch: { _, _ in }
    )
}
