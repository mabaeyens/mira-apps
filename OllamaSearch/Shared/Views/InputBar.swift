import SwiftUI
import UniformTypeIdentifiers

/// Compose bar at the bottom of the chat view.
/// Two-row card: top row is the text field; bottom row has +, chips, model pill, and send/stop.
/// Tapping + opens an "Add to Chat" sheet with file attachment and thinking toggle.
struct InputBar: View {
    @Bindable var vm: ChatViewModel

    @FocusState private var isFocused: Bool
    @State private var showAddToChat = false
    #if os(iOS)
    @State private var showFilePicker = false
    #endif

    var body: some View {
        VStack(spacing: 6) {
            // ── Staged attachment chips ───────────────────────────────────────
            if !vm.stagedAttachmentNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(vm.stagedAttachmentNames.enumerated()), id: \.offset) { idx, name in
                            attachmentChip(name: name, index: idx)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // ── Two-row card ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Top: text field
                TextField("Message…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.chatBody)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .focused($isFocused)
                    .onSubmit {
                        guard !vm.isStreaming else { return }
                        isFocused = false
                        vm.send()
                    }
                    .keyboardShortcut(.return, modifiers: .command)

                // Thin divider between rows
                Color.borderSubtle.opacity(0.4).frame(height: 0.5)

                // Bottom: + | chips | spacer | model▾ | send/stop
                HStack(alignment: .center, spacing: 8) {
                    // + button
                    Button { showAddToChat = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .focusEffectDisabled()
                    #endif

                    // Thinking chip — visible only when ON; tap to turn off
                    if vm.thinkingEnabled {
                        Button { vm.thinkingEnabled = false } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.fill")
                                    .font(.system(size: 10))
                                Text("Thinking")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Active project chip — read-only indicator
                    if let project = vm.activeProject {
                        HStack(spacing: 3) {
                            Image(systemName: project.localPath != nil ? "folder" : "network")
                                .font(.system(size: 9, weight: .medium))
                            Text(project.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    // Model switcher pill
                    Button { vm.showModelPicker = true } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(modelStatusColor)
                                .frame(width: 6, height: 6)
                            Text(vm.modelName.isEmpty
                                ? (vm.currentBackend == "omlx" ? "oMLX" : "Ollama")
                                : vm.modelName)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.textSecondary)
                                .opacity(0.7)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.surfaceBg)
                                .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSwitchingBackend)
                    #if os(macOS)
                    .focusEffectDisabled()
                    #endif

                    actionButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.borderSubtle.opacity(0.6), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(Color.appBg)
        .animation(.spring(duration: 0.2), value: vm.thinkingEnabled)
        .sheet(isPresented: $showAddToChat) {
            addToChatSheet
        }
        #if os(iOS)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText, .html, .png, .jpeg, .gif, .webP, .bmp],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    vm.errorMessage = "Could not access: \(url.lastPathComponent)"
                    continue
                }
                Task.detached {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                                   ?? "application/octet-stream"
                        await MainActor.run {
                            self.vm.pendingAttachments.append(.fileData(name: url.lastPathComponent, data: data, mimeType: mime))
                            self.vm.stagedAttachmentNames.append(url.lastPathComponent)
                        }
                    } else {
                        await MainActor.run {
                            self.vm.errorMessage = "Could not load: \(url.lastPathComponent)"
                        }
                    }
                }
            }
        }
        #endif
    }

    // ── "Add to Chat" sheet ───────────────────────────────────────────────────────

    private var addToChatSheet: some View {
        VStack(spacing: 0) {
            // Pull handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Add to Chat")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .padding(.vertical, 14)

            Divider().background(Color.borderSubtle)

            // Files row
            Button {
                showAddToChat = false
                #if os(macOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    attachFilesMacOS()
                }
                #elseif os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showFilePicker = true
                }
                #endif
            } label: {
                addToChatRow(
                    icon: "paperclip",
                    label: "Files & Images",
                    trailing: nil
                )
            }
            .buttonStyle(.plain)

            Divider().background(Color.borderSubtle.opacity(0.5))

            // Thinking row
            Button {
                showAddToChat = false
                vm.thinkingEnabled.toggle()
            } label: {
                addToChatRow(
                    icon: vm.thinkingEnabled ? "brain.fill" : "brain",
                    label: "Thinking",
                    trailing: vm.thinkingEnabled ? "On" : "Off",
                    iconColor: vm.thinkingEnabled ? Color.appAccent : Color.textSecondary
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBg)
        .presentationDetents([.height(230)])
        .presentationDragIndicator(.hidden)
    }

    private func addToChatRow(
        icon: String,
        label: String,
        trailing: String?,
        iconColor: Color = Color.textSecondary
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.surfaceBg)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // ── macOS file picker ─────────────────────────────────────────────────────────

    #if os(macOS)
    private func attachFilesMacOS() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, .html, .png, .jpeg, .gif, .webP, .bmp]
        panel.title = "Attach files"
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task.detached {
            var loaded: [(name: String, data: Data, mime: String)] = []
            var failed: [String] = []
            for url in urls {
                if let data = try? Data(contentsOf: url) {
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                               ?? "application/octet-stream"
                    loaded.append((url.lastPathComponent, data, mime))
                } else {
                    failed.append(url.lastPathComponent)
                }
            }
            await MainActor.run {
                for att in loaded {
                    self.vm.pendingAttachments.append(.fileData(name: att.name, data: att.data, mimeType: att.mime))
                    self.vm.stagedAttachmentNames.append(att.name)
                }
                if !failed.isEmpty {
                    self.vm.errorMessage = "Could not load: \(failed.joined(separator: ", "))"
                }
            }
        }
    }
    #endif

    // ── Send / Stop button ────────────────────────────────────────────────────────

    private var modelStatusColor: Color {
        if vm.errorMessage != nil { return .red }
        if vm.isSwitchingBackend || vm.isStartingBackend { return .yellow }
        if vm.backendReady { return .green }
        return Color(white: 0.45)
    }

    @ViewBuilder
    private var actionButton: some View {
        if vm.isStreaming {
            Button(action: { vm.stopStreaming() }) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        } else {
            let canSend = !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                isFocused = false
                vm.send()
            } label: {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(canSend ? Color.accent : Color.borderSubtle))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    // ── Attachment chip ───────────────────────────────────────────────────────────

    private func attachmentChip(name: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.caption2)
                .foregroundStyle(Color.accent)
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Color.textPrimary)
            Button {
                vm.pendingAttachments.remove(at: index)
                vm.stagedAttachmentNames.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.surfaceBg)
                .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
        )
    }
}
