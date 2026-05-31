#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// Paper-clip button using UIDocumentPickerViewController for iOS.
struct iOSAttachButton: View {
    @Environment(ChatViewModel.self) private var vm
    @State private var isPresented = false

    private let allowedTypes: [UTType] = [
        .pdf, .plainText, .html, .png, .jpeg, .gif, .webP, .bmp
    ]

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                // Security-scoped access must be started before the background
                // read and stopped only after the read finishes.
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
    }
}

#endif
