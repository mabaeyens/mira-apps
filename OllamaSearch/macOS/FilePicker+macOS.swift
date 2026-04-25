#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Paper-clip button that opens NSOpenPanel (multi-select, filtered extensions).
/// Injects selected files as `AttachmentPayload.fileData` into the view model.
struct MacAttachButton: View {
    @Bindable var vm: ChatViewModel

    private let allowedTypes: [UTType] = [
        .pdf, .plainText, .html, .png, .jpeg, .gif, .webP, .bmp
    ]

    var body: some View {
        Button {
            openPanel()
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16))
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
}

#endif
