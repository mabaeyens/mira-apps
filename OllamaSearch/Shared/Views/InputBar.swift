import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// Compose bar at the bottom of the chat view.
/// Two-row card: top row is the text field; bottom row has +, chips, model pill, and send/stop.
/// Tapping + opens an "Add to Chat" sheet with file attachment and thinking toggle.
struct InputBar: View {
    @Environment(ChatViewModel.self) private var vm
    @Environment(CloudPreferences.self) private var prefs

    // Optional external binding lets the pill + button in ChatView trigger this sheet.
    var showSheetExternal: Binding<Bool>? = nil
    @State private var _showAddToChat = false
    private var showAddToChat: Binding<Bool> { showSheetExternal ?? $_showAddToChat }

    @FocusState private var isFocused: Bool
    @State private var sr = SpeechRecognizer()
    #if os(iOS)
    @State private var showFilePicker = false
    @State private var showCameraPicker = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showProjectPicker = false
    #endif

    // Icon-glyph sizes that map onto no stock text style, scaled so the glyphs
    // grow with Dynamic Type. Base values equal the former literals, so nothing
    // changes at the default size; their (still-fixed) frames are a later pass.
    // On macOS these resolve to the base value, so the surface stays fixed there.
    @ScaledMetric(relativeTo: .caption)  private var brainGlyphAdaptive: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var brainGlyphCompact: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var projectPillGlyph: CGFloat = 9
    @ScaledMetric(relativeTo: .title)    private var attachTileGlyph: CGFloat = 26

    /// 12pt medium pill label. Scales on iOS (.caption is 12); macOS keeps a
    /// fixed 12 (its .caption is 10, too small for these controls).
    private var pillCaption: Font {
        #if os(iOS)
        .caption.weight(.medium)
        #else
        .system(size: 12, weight: .medium)
        #endif
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            attachmentChipsRow()

            // ── Two-row card ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                textFieldRow()
                Color.borderSubtle.opacity(0.4).frame(height: 0.5)
                toolbarRow()
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.compose)
                    .fill(Color.surfaceBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.compose)
                            .strokeBorder(Color.borderSubtle.opacity(0.6), lineWidth: 1)
                    )
            )
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.ml)
        }
        .background(Color.appBg)
        .animation(.spring(duration: 0.2), value: vm.thinkingMode)
        #if os(iOS)
        .sheet(isPresented: showAddToChat) {
            addToChatSheetIOS
        }
        #endif
        #if os(iOS)
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let name = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                        await MainActor.run {
                            vm.pendingAttachments.append(.fileData(name: name, data: data, mimeType: "image/jpeg"))
                            vm.stagedAttachmentNames.append(name)
                        }
                    }
                }
                await MainActor.run { selectedPhotos = [] }
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView(isPresented: $showCameraPicker) { data in
                let name = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                vm.pendingAttachments.append(.fileData(name: name, data: data, mimeType: "image/jpeg"))
                vm.stagedAttachmentNames.append(name)
                showAddToChat.wrappedValue = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showProjectPicker) {
            projectPickerSheet
        }
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
        .onChange(of: sr.transcript) { _, newVal in
            if !newVal.isEmpty { vm.inputText = newVal }
        }
        .onChange(of: vm.isSwitchingBackend) { _, switching in
            if switching && sr.isRecording { sr.stop() }
        }
        .alert("Microphone Access", isPresented: Binding(
            get: { sr.error != nil },
            set: { if !$0 { sr.error = nil } }
        )) {
            Button("OK") { sr.error = nil }
        } message: {
            Text(sr.error ?? "")
        }
        #endif
    }

    // ── Attachment chips row ──────────────────────────────────────────────────────

    @ViewBuilder
    private func attachmentChipsRow() -> some View {
        if !vm.stagedAttachmentNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(Array(vm.stagedAttachmentNames.enumerated()), id: \.offset) { idx, name in
                        attachmentChip(name: name, index: idx)
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }
        }
    }

    // ── Text field row ────────────────────────────────────────────────────────────

    private func textFieldRow() -> some View {
        TextField("Message…", text: Bindable(vm).inputText, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.chatBody)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.l)
            .padding(.top, 13)
            .padding(.bottom, 11)
            .focused($isFocused)
            .onSubmit {
                guard !vm.isStreaming else { return }
                isFocused = false
                vm.send()
            }
            .keyboardShortcut(.return, modifiers: .command)
    }

    // ── Toolbar row ───────────────────────────────────────────────────────────────

    private func toolbarRow() -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Button { showAddToChat.wrappedValue = true } label: {
                Image(systemName: "plus")
                    .font(.iconCompact.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .focusEffectDisabled()
            .popover(isPresented: showAddToChat, arrowEdge: .bottom) {
                addToChatPopoverMac
            }
            #endif

            // Thinking toggle — cycles: off → adaptive → on → off
            Button { vm.thinkingMode.cycle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "brain.fill")
                        .font(.system(size: vm.thinkingMode == .adaptive ? brainGlyphAdaptive : brainGlyphCompact, weight: .medium))
                    switch vm.thinkingMode {
                    case .on:
                        Text("Thinking")
                            .font(pillCaption)
                    case .off:
                        Text("Off")
                            .font(pillCaption)
                    case .adaptive:
                        Text("Auto")
                            .font(pillCaption)
                    }
                }
                .foregroundStyle(vm.thinkingMode == .on ? Color.appAccent : Color.textSecondary.opacity(0.6))
                .padding(.horizontal, 7)
                .frame(minHeight: 28)
                .background(
                    vm.thinkingMode == .on ? Color.appAccent.opacity(0.12) : Color.textSecondary.opacity(0.08),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .focusEffectDisabled()
            #endif
            .help(vm.thinkingMode == .adaptive ? "Mira decides automatically" : vm.thinkingMode == .on ? "Thinking forced on" : "Thinking forced off")

            if let project = vm.activeProject {
                HStack(spacing: 3) {
                    Image(systemName: project.localPath != nil ? "folder" : "network")
                        .font(.system(size: projectPillGlyph, weight: .medium))
                    Text(project.name)
                        .font(pillCaption)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.appAccent.opacity(0.12), in: Capsule())
            }

            Spacer()

            modelPill()
            micButton
            actionButton
        }
        .padding(.horizontal, Spacing.ml)
        .padding(.vertical, Spacing.sm)
    }

    // ── Model pill ────────────────────────────────────────────────────────────────

    private func modelPill() -> some View {
        Button { vm.showModelPicker = true } label: {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(modelStatusColor)
                    .frame(width: 6, height: 6)
                Text(vm.modelName.isEmpty ? vm.runningLabel : vm.modelDisplayName)
                    .font(.pillLabel)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(Color.surfaceBg)
                    .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isSwitchingBackend || vm.isStreaming)
    }

    // ── "Add to Chat" popover — macOS ────────────────────────────────────────────

    #if os(macOS)
    private var addToChatPopoverMac: some View {
        VStack(spacing: 0) {
            Button {
                showAddToChat.wrappedValue = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    attachFilesMacOS()
                }
            } label: {
                addToChatRow(icon: "paperclip", label: "Files & Images", trailing: nil)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, Spacing.ml)

            HStack(spacing: Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(Color.surfaceBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: "mic")
                        .font(.iconMedium.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                Text("Speech language")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: Bindable(prefs).speechLanguage) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en-US")
                    Text("Español").tag("es-ES")
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.ml)

            Divider()
                .padding(.horizontal, Spacing.ml)

            Button { vm.thinkingMode.cycle() } label: {
                addToChatRow(
                    icon: "brain.fill",
                    label: "Thinking",
                    trailing: vm.thinkingMode == .on ? "On" : vm.thinkingMode == .off ? "Off" : "Auto"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(vm.thinkingMode == .on ? Color.appAccent : Color.textPrimary)
        }
        .frame(width: 320)
        .padding(.vertical, Spacing.xs)
        .background(Color.appBg)
    }
    #endif

    // ── "Add to Chat" sheet — macOS (kept for reference, no longer presented) ────

    private var addToChatSheet: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, Spacing.m)

            Text("Add to Chat")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .padding(.vertical, Spacing.l)

            Divider().background(Color.borderSubtle)

            Button {
                showAddToChat.wrappedValue = false
                #if os(macOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    attachFilesMacOS()
                }
                #endif
            } label: {
                addToChatRow(icon: "paperclip", label: "Files & Images", trailing: nil)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBg)
        .presentationDetents([.height(180)])
        .presentationDragIndicator(.hidden)
    }

    // ── "Add to Chat" sheet — iOS (Claude-style grid) ─────────────────────────

    #if os(iOS)
    private var addToChatSheetIOS: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 8)

            Text("Add to Chat")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .padding(.vertical, Spacing.l)

            // ── 3-tile grid ───────────────────────────────────────────────────
            HStack(spacing: Spacing.ml) {
                attachmentTile(icon: "camera.fill", label: "Camera",
                               color: Color(uiColor: .systemBlue)) {
                    showAddToChat.wrappedValue = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showCameraPicker = true
                    }
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                attachmentTile(icon: "photo.fill", label: "Photos",
                               color: Color(uiColor: .systemGreen)) {
                    showAddToChat.wrappedValue = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPhotosPicker = true
                    }
                }

                attachmentTile(icon: "arrow.up.doc.fill", label: "Files",
                               color: Color(uiColor: .systemOrange)) {
                    showAddToChat.wrappedValue = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showFilePicker = true
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xl)

            Divider().padding(.horizontal, Spacing.xl)

            // ── Add to project row ────────────────────────────────────────────
            Button(action: { showProjectPicker = true }) {
                addToChatRow(
                    icon: "folder.badge.plus",
                    label: "Add to project",
                    trailing: vm.activeProject?.name
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, Spacing.xl)

            // ── Speech language row ───────────────────────────────────────────
            HStack(spacing: Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(Color.surfaceBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: "mic.fill")
                        .font(.title3.weight(.medium)) // 20pt, scales — canonical sheet row icon
                        .foregroundStyle(Color.textSecondary)
                }
                Text("Speech language")
                    .font(.body) // 17pt, scales — canonical sheet row label
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: Bindable(prefs).speechLanguage) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en-US")
                    Text("Español").tag("es-ES")
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.ml)
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBg)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func attachmentTile(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.compose)
                        .fill(color.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: attachTileGlyph, weight: .medium))
                        .foregroundStyle(color)
                }
                .frame(height: 72)
                Text(label)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var projectPickerSheet: some View {
        NavigationStack {
            Group {
                if vm.projects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.projects) { project in
                        Button(action: {
                            vm.setProject(project.id, for: vm.currentConvId)
                            showProjectPicker = false
                        }) {
                            HStack(spacing: Spacing.ml) {
                                Image(systemName: project.icon)
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 20)
                                Text(project.name)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showProjectPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    #endif

    private func addToChatRow(
        icon: String,
        label: String,
        trailing: String?,
        iconColor: Color = Color.textSecondary
    ) -> some View {
        HStack(spacing: Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.surfaceBg)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    #if os(iOS)
                    .font(.title3.weight(.medium)) // 20pt, scales — canonical sheet row icon
                    #else
                    .font(.iconMedium.weight(.medium)) // macOS: keep 17 (.title3 is only 15pt here)
                    #endif
                    .foregroundStyle(iconColor)
            }
            Text(label)
                #if os(iOS)
                .font(.body)             // 17pt, scales — canonical sheet row label
                #else
                .font(.system(size: 16)) // macOS .body is 13; keep fixed
                #endif
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let t = trailing {
                Text(t)
                    #if os(iOS)
                    .font(.subheadline)      // 15pt, scales
                    #else
                    .font(.system(size: 15)) // macOS .subheadline is 11; keep fixed
                    #endif
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.ml)
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
            // Snapshot into immutable values before hopping to the main actor so the
            // closure doesn't capture the mutable vars (Swift 6 concurrency).
            let loadedFinal = loaded
            let failedFinal = failed
            await MainActor.run {
                for att in loadedFinal {
                    self.vm.pendingAttachments.append(.fileData(name: att.name, data: att.data, mimeType: att.mime))
                    self.vm.stagedAttachmentNames.append(att.name)
                }
                if !failedFinal.isEmpty {
                    self.vm.errorMessage = "Could not load: \(failedFinal.joined(separator: ", "))"
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

    private var micButton: some View {
        Button {
            Task {
                if sr.isRecording { sr.stop() }
                else { await sr.start(localeTag: prefs.speechLanguage) }
            }
        } label: {
            Image(systemName: sr.isRecording ? "mic.fill" : "mic")
                .font(.iconCompact.weight(.medium))
                .foregroundStyle(sr.isRecording ? Color.accent : Color.textSecondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(vm.isStreaming || vm.isSwitchingBackend)
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
        HStack(spacing: Spacing.xs) {
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
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule().fill(Color.surfaceBg)
                .overlay(Capsule().strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 1))
        )
    }
}

// ── Camera picker (UIImagePickerController bridge) ────────────────────────────

#if os(iOS)
private struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
#endif
