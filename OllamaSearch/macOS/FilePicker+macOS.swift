#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Paper-clip button that opens NSOpenPanel (multi-select, filtered extensions).
/// Injects selected files as `AttachmentPayload.fileData` into the view model.
struct MacAttachButton: View {
    @Environment(ChatViewModel.self) private var vm

    private let allowedTypes: [UTType] = [
        .pdf, .plainText, .html, .png, .jpeg, .gif, .webP, .bmp
    ]

    var body: some View {
        Button {
            openPanel()
        } label: {
            Image(systemName: "paperclip")
                .font(.iconMedium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Attach files (PDF, images, text, HTML)")
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedTypes
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
}

#endif
