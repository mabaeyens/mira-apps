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

        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                       ?? "application/octet-stream"
            vm.pendingAttachments.append(
                .fileData(name: url.lastPathComponent, data: data, mimeType: mime)
            )
            vm.stagedAttachmentNames.append(url.lastPathComponent)
        }
    }
}

#endif
