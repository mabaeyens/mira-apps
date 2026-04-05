import SwiftUI
import UniformTypeIdentifiers

/// Paper-clip button using UIDocumentPickerViewController for iOS.
struct iOSAttachButton: View {
    @Bindable var vm: ChatViewModel
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
                // UIDocumentPicker gives us a security-scoped URL —
                // must call startAccessingSecurityScopedResource.
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
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
}
